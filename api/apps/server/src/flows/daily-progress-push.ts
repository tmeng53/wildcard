import { MemberId as CheckInMember, SquadId, type CheckIns } from '@wildcard/check-ins';
import type { Members } from '@wildcard/members';
import {
  LocalDay,
  MemberId as PushMember,
  type DailyCandidate,
  type Push,
  type PushNotification,
} from '@wildcard/push';
import { MemberId as SquadMember, type Squads } from '@wildcard/squads';

import type { Log } from '../log.js';

/** How many members' pushes are put together at once. */
const AT_ONCE = 4;

/**
 * Teammates who did something for a member, by kind (`reaction`, and later a poke): each person
 * once per kind. The kind is the name the app's String Catalog keys the copy by.
 */
export type Interactions = ReadonlyMap<string, ReadonlySet<string>>;

/**
 * Where one sort of interaction comes from: reactions now, pokes and others as they land. A new
 * kind of interaction is one more source, or one more kind from an existing one; nothing else
 * in the daily push changes.
 */
export type InteractionSource = (query: {
  readonly member: string;
  readonly since: Date;
  readonly until: Date;
}) => Promise<Interactions>;

/** The interactions sources built on check-ins: teammates' reactions, with any emoji. */
export function reactionInteractions(checkIns: CheckIns): InteractionSource {
  return async ({ member, since, until }) => {
    const people = await checkIns.reactionsReceived({
      member: CheckInMember.parse(member),
      since,
      until,
    });
    return new Map([['reaction', people]]);
  };
}

export interface DailyProgressDependencies {
  readonly members: Members;
  readonly squads: Squads;
  readonly checkIns: CheckIns;
  readonly push: Push;
  readonly interactions: readonly InteractionSource[];
  readonly clock: () => Date;
  readonly log: Log;
}

/** What a run did, member by member. */
export interface DailyProgressRun {
  /** Members whose push was due: past the hour, a phone, not turned off, not handled today. */
  readonly due: number;
  /** Reached at least one of the member's phones. */
  readonly sent: number;
  /** Had something to say but reached no phone: sending is off, or every phone failed. */
  readonly unsent: number;
  /** Handled with nothing to say: no squad, or no one in it checked in and nothing came in. */
  readonly quiet: number;
  /** Another run handled them first. */
  readonly skipped: number;
  /** Failed before their day was claimed; tried again on the next run. */
  readonly failed: number;
}

/**
 * Sends each member their one push of the day once their clock passes the hour the push settings
 * name (6pm to begin with): the squad's week so
 * far and who reacted to, poked or otherwise cheered them on since their last one. Meant to run
 * every few minutes; each member's day is handled once, claimed before sending, so runs can overlap or
 * repeat. A member whose squad was quiet and who got nothing gets no push that day.
 */
export async function sendDailyProgress(
  deps: DailyProgressDependencies,
): Promise<DailyProgressRun> {
  const now = deps.clock();
  const settings = await deps.push.dailySettings();
  // Switched off for everyone: nobody is due, and nobody's day is marked handled.
  if (!settings.sending) return { due: 0, sent: 0, unsent: 0, quiet: 0, skipped: 0, failed: 0 };
  const evening = await deps.members.pastLocalHour({ hour: settings.hour, now });
  const dayBefore = new Map<string, Date>(
    evening.map(({ member, hourTheDayBefore }) => [member, hourTheDayBefore]),
  );
  const due = await deps.push.dailyDue(
    evening.map(({ member, day }) => ({
      member: PushMember.parse(member),
      day: LocalDay.parse(day),
    })),
  );
  const outcomes: Outcome[] = [];
  for (let start = 0; start < due.length; start += AT_ONCE) {
    const batch = due.slice(start, start + AT_ONCE);
    outcomes.push(
      ...(await Promise.all(
        batch.map(async (each) => {
          // Always there: every member due is one of this evening's.
          const earliest = dayBefore.get(each.member);
          if (earliest === undefined) return 'failed';
          const last = each.lastHandledAt ?? earliest;
          return handle(deps, { ...each, since: last > earliest ? last : earliest, until: now });
        }),
      )),
    );
  }
  const count = (outcome: Outcome) => outcomes.filter((each) => each === outcome).length;
  return {
    due: due.length,
    sent: count('sent'),
    unsent: count('unsent'),
    quiet: count('quiet'),
    skipped: count('skipped'),
    failed: count('failed'),
  };
}

type Outcome = 'sent' | 'unsent' | 'quiet' | 'skipped' | 'failed';

/**
 * A member whose push is due, and what it covers: from their last one (or the push hour on their clock the
 * day before, if that is later) to this run, which their day is then handled at. So consecutive
 * pushes meet, and nothing is counted twice or left out, whenever in the evening a run reaches
 * them.
 */
type Due = DailyCandidate & { readonly since: Date; readonly until: Date };

/** One member's push. Never throws, so one member's failure never stops the others'. */
async function handle(deps: DailyProgressDependencies, due: Due): Promise<Outcome> {
  const { member, day, until } = due;
  let notification: PushNotification | undefined;
  try {
    notification = await compose(deps, due);
    const quiet = notification === undefined;
    if (!(await deps.push.claimDaily({ member, day, quiet, at: until }))) return 'skipped';
    if (notification === undefined) return 'quiet';
  } catch (error) {
    deps.log.error('daily push not put together', { member, day, error });
    return 'failed';
  }
  try {
    const outcome = await deps.push.notifyMembers({ members: [member], notification });
    if (outcome.failures.length > 0) {
      deps.log.warn('daily push not sent to every phone', { member, failures: outcome.failures });
    }
    return outcome.sent > 0 ? 'sent' : 'unsent';
  } catch (error) {
    // Claimed already, so it isn't tried again: at most one push a day.
    deps.log.error('daily push not sent', { member, day, error });
    return 'unsent';
  }
}

/** The member's push for today, or `undefined` when there is nothing to tell them. */
async function compose(
  deps: DailyProgressDependencies,
  { member, day, since, until }: Due,
): Promise<PushNotification | undefined> {
  // The squad the app shows: the one they joined first.
  const [squad] = await deps.squads.listMine(SquadMember.parse(member));
  if (squad === undefined) return undefined;
  const window = { member, since, until };
  const [today, ...received] = await Promise.all([
    deps.checkIns.squadToday({
      viewer: CheckInMember.parse(member),
      squad: SquadId.parse(squad.id),
    }),
    ...deps.interactions.map((source) => source(window)),
  ]);
  const byKind = mergeInteractions(received);
  const squadCheckedIn = today.members.some(({ firstCheckInAt }) => firstCheckInAt !== undefined);
  if (!squadCheckedIn && byKind.size === 0) return undefined;
  return dailyProgressNotification({
    day,
    squad: squad.id,
    squadWeek: today.squadWeek,
    received: byKind,
  });
}

/** One set of people per kind, from every source. */
function mergeInteractions(all: readonly Interactions[]): Map<string, Set<string>> {
  const merged = new Map<string, Set<string>>();
  for (const interactions of all) {
    for (const [kind, people] of interactions) {
      if (people.size === 0) continue;
      merged.set(kind, new Set([...(merged.get(kind) ?? []), ...people]));
    }
  }
  return merged;
}

/**
 * The daily push, without its words: the alert names a String Catalog key with the squad's week
 * (and how many teammates did something for the member), and `event` carries the people per
 * kind, for the app's notification service extension to write one line per kind, such as
 * 「3 人给你点了表情，2 人催你练了」.
 */
export function dailyProgressNotification({
  day,
  squad,
  squadWeek,
  received,
}: {
  readonly day: string;
  readonly squad: string;
  readonly squadWeek: { readonly trainedDays: number; readonly plannedDays: number };
  readonly received: Interactions;
}): PushNotification {
  const people = new Set([...received.values()].flatMap((each) => [...each])).size;
  const week = [String(squadWeek.trainedDays), String(squadWeek.plannedDays)];
  return {
    alert:
      people === 0
        ? { key: 'push.dailyProgress', args: week }
        : { key: 'push.dailyProgress.received', args: [...week, String(people)] },
    category: 'dailyProgress',
    thread: 'dailyProgress',
    collapseId: `dailyProgress-${day}`,
    interruption: 'passive',
    mutableContent: true,
    event: {
      kind: 'dailyProgress',
      day,
      squad,
      squadTrainedDays: squadWeek.trainedDays,
      squadPlannedDays: squadWeek.plannedDays,
      received: Object.fromEntries([...received].map(([kind, each]) => [kind, each.size])),
    },
  };
}
