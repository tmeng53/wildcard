import {
  MemberId as CheckInMember,
  SquadId as CheckInSquad,
  WeekStart as CheckInWeek,
  type CheckIns,
} from '@wildcard/check-ins';
import {
  MemberId as NoticeMember,
  SquadId as NoticeSquad,
  type NewNotice,
  type Notices,
} from '@wildcard/notices';
import {
  SUGGESTION_WEEKS,
  SceneWeek,
  SquadId,
  goalFor,
  overGoal,
  suggestedGoal,
  weekAfter,
  weeksBefore,
  type GoalSuggestion,
  type GoalWeek,
  type MemberId,
  type Squads,
  type WeeklyGoalSetting,
} from '@wildcard/squads';
import { awardsTimeOf, latestAwardedWeek } from '@wildcard/weekly-awards';

import type { Log } from '../log.js';
import type { Database } from '../ports.js';

// 连续 3 周超过小队目标: a squad's weeks against its goal, from squads (who was in it, its goal,
// its captain and what they were suggested before) and check-ins (the days trained for it), told
// to the captain through notices.

export interface GoalSuggestionDependencies {
  readonly checkIns: Pick<CheckIns, 'squadsCheckedInto' | 'squadTrainedDays'>;
  readonly squads: Pick<Squads, 'captainOf' | 'goalSuggestions' | 'membersAt' | 'weeklyGoals'>;
  /** Keeps the suggestion and tells the captain, both or neither (`suggestGoalIn`). */
  readonly suggestGoal: SuggestGoal;
  readonly clock: () => Date;
  readonly log: Log;
}

/**
 * Keeps a suggestion in the squad's log and its notice in the captain's 通知 together: 'taken'
 * when the squad was already told that week. Both or neither, so a notice that can't be kept
 * leaves the week to the next run instead of a suggestion nobody heard.
 */
export type SuggestGoal = (input: {
  readonly squad: SquadId;
  readonly suggestion: GoalSuggestion;
  readonly notice: NewNotice;
}) => Promise<'suggested' | 'taken'>;

/** `SuggestGoal` in one transaction of `db`, on the squads and notices it opens there. */
export function suggestGoalIn(
  db: Database,
  on: {
    readonly squads: (scope: Database) => Pick<Squads, 'suggestGoal'>;
    readonly notices: (scope: Database) => Pick<Notices, 'tell'>;
  },
): SuggestGoal {
  return ({ squad, suggestion, notice }) =>
    db.transaction().execute(async (trx) => {
      const outcome = await on.squads(trx).suggestGoal(squad, suggestion);
      if (outcome === 'suggested') await on.notices(trx).tell([notice]);
      return outcome;
    });
}

/** What a run did. */
export interface GoalSuggestionRun {
  /** The week whose 战报 froze last: the latest of the weeks counted. */
  readonly week: string;
  /** Squads that trained for it before its 战报. */
  readonly squads: number;
  /** Captains told a higher goal this run. */
  readonly suggested: number;
  /** Squads that couldn't be checked; the next run tries again. */
  readonly failed: number;
}

/**
 * Once the latest week's 战报 froze (Sunday 8pm New York), tells the captain of each squad that
 * trained over its goal in that week and the two before it a higher goal to try: the days each
 * member trained on average then, rounded, at most 7, and only above the goal it has from next
 * week. A captain is told once a run of weeks over: a squad that stays over isn't told again
 * until a week under breaks it, unless its captain changed. Meant to run every hour, after the
 * awards: a squad told already that week is only checked.
 */
export async function suggestSquadGoals(
  deps: GoalSuggestionDependencies,
): Promise<GoalSuggestionRun> {
  const awarded = latestAwardedWeek(deps.clock());
  const week = SceneWeek.parse(awarded);
  const squads = await deps.checkIns.squadsCheckedInto({
    weekStart: CheckInWeek.parse(week),
    before: awardsTimeOf(awarded),
  });
  let suggested = 0;
  let failed = 0;
  for (const squad of squads) {
    try {
      if (await suggestTo(deps, { squad: SquadId.parse(squad), week })) suggested += 1;
    } catch (error) {
      failed += 1;
      deps.log.error('a squad’s goal suggestion failed; the next run tries again', {
        squad,
        week,
        error,
      });
    }
  }
  return { week, squads: squads.length, suggested, failed };
}

/** Tells the squad's captain a higher goal after `week`, if it is due; whether it told them. */
async function suggestTo(
  deps: GoalSuggestionDependencies,
  { squad, week }: { readonly squad: SquadId; readonly week: SceneWeek },
): Promise<boolean> {
  const [captain, settings, earlier] = await Promise.all([
    deps.squads.captainOf(squad),
    deps.squads.weeklyGoals(squad),
    deps.squads.goalSuggestions(squad),
  ]);
  if (captain === undefined || earlier.some((each) => each.week === week)) return false;
  const counter = weekCounter(deps, { squad, settings });
  const weeks: GoalWeek[] = [];
  for (let back = SUGGESTION_WEEKS - 1; back >= 0; back -= 1) {
    weeks.push(await counter(weeksBefore(week, back)));
  }
  const daysPerMember = suggestedGoal({ weeks, next: goalFor(settings, weekAfter(week)) });
  if (daysPerMember === undefined) return false;
  // Once a run of weeks over: told this captain since the last week under, they aren't again.
  const last = earlier.findLast((each) => each.captain === captain);
  if (last !== undefined && (await overSince(counter, { from: last.week, to: weeks[0]?.week }))) {
    return false;
  }
  const outcome = await deps.suggestGoal({
    squad,
    suggestion: { week, captain, daysPerMember },
    notice: captainsNotice({ squad, captain, daysPerMember }),
  });
  return outcome === 'suggested';
}

/** Whether every week after `from` and before `to` was over its goal. */
async function overSince(
  counter: (week: SceneWeek) => Promise<GoalWeek>,
  { from, to }: { readonly from: SceneWeek; readonly to: SceneWeek | undefined },
): Promise<boolean> {
  if (to === undefined) return false;
  for (let week = weekAfter(from); week < to; week = weekAfter(week)) {
    if (!overGoal(await counter(week))) return false;
  }
  return true;
}

/** Counts one of the squad's weeks: its trained days, members at its end and goal. */
function weekCounter(
  deps: GoalSuggestionDependencies,
  { squad, settings }: { readonly squad: SquadId; readonly settings: readonly WeeklyGoalSetting[] },
): (week: SceneWeek) => Promise<GoalWeek> {
  return async (week) => {
    // A week not over yet counts whoever is in the squad now.
    const end = Math.min(Date.parse(weekAfter(week)), deps.clock().getTime());
    const members = await deps.squads.membersAt(squad, new Date(end));
    const trainedDays =
      members.length === 0
        ? 0
        : await deps.checkIns.squadTrainedDays({
            squad: CheckInSquad.parse(squad),
            members: members.map((member) => CheckInMember.parse(member)),
            weekStart: CheckInWeek.parse(week),
          });
    return { week, trainedDays, members: members.length, daysPerMember: goalFor(settings, week) };
  };
}

/** The captain's notice: in 通知 and, once on each phone, the home's banner. Never a push. */
function captainsNotice(input: {
  readonly squad: SquadId;
  readonly captain: MemberId;
  readonly daysPerMember: number;
}): NewNotice {
  return {
    member: NoticeMember.parse(input.captain),
    squad: NoticeSquad.parse(input.squad),
    kind: 'goalSuggestion',
    subject: { version: 1, weeks: SUGGESTION_WEEKS, daysPerMember: input.daysPerMember },
  };
}
