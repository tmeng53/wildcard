import {
  SquadId as CheckInSquad,
  WeekStart as CheckInWeek,
  photosOf,
  type CheckInRecord,
  type CheckIns,
  type StoryDay,
  type SquadWeekCheckIns,
} from '@wildcard/check-ins';
import type { Admins } from '@wildcard/admins';
import type { Members } from '@wildcard/members';
import { MemberId as PushMember, type Push, type PushNotification } from '@wildcard/push';
import { MemberId as SquadsMember, SquadId as SquadsSquad, type Squads } from '@wildcard/squads';
import {
  MemberId,
  awardsTimeOf,
  latestAwardedWeek,
  topCheckInOf,
  type AwardMove,
  type Failures,
  type HottestWords,
  type MemberAwards,
  type MemberWeek,
  type MiddlePage,
  type SquadId,
  type SquadPages,
  type TopCheckIn,
  type WeekCheckIn,
  WeekStart,
  type WeeklyAwards,
  WeekStoryNotReadyError,
} from '@wildcard/weekly-awards';

import type { Log } from '../log.js';

// The weekly awards across modules: the week's check-ins from check-ins, members' clocks from
// members, the awards from weekly-awards, the winners' push from push, and the admins a nudge
// tells from admins.

export interface WeeklyAwardsDependencies {
  readonly checkIns: CheckIns;
  readonly members: Members;
  readonly squads: Squads;
  readonly awards: WeeklyAwards;
  readonly push: Push;
  readonly admins: Pick<Admins, 'list'>;
  readonly clock: () => Date;
  readonly log: Log;
}

/** What a run did, squad by squad. */
export interface WeeklyAwardsRun {
  /** The weeks whose awards it gave: the latest, and the one before for squads still failing. */
  readonly weeks: readonly WeekStart[];
  /** Squads with a check-in for the week made before the awards. */
  readonly squads: number;
  /** Squads whose awards this run wrote. */
  readonly given: number;
  /** Squads whose awards couldn't be written; the next run tries again. */
  readonly failed: number;
  /** Winners this run told, each once a squad. */
  readonly told: number;
}

/**
 * The winners' push. It says only that the awards are in, never what anyone won, so opening the
 * story is the surprise. A later one for the same week (a member in two squads) replaces it.
 */
export function awardsReadyNotification(squad: SquadId, week: WeekStart): PushNotification {
  return {
    alert: { key: 'push.weeklyAwards.ready' },
    category: 'weeklyAwards',
    thread: 'weekly-awards',
    collapseId: `weekly-awards-${week}`,
    interruption: 'active',
    event: { squad, weekStart: week },
  };
}

/**
 * The admins' push when a member nudges about awards that haven't come: which squad, how many
 * tries failed and why the last one did (often the model's account is out of credit), so an
 * admin knows what to fix. The app's copy is a reminder to top up.
 */
export function awardsStuckNotification({
  squad,
  week,
  failures,
}: {
  readonly squad: { readonly id: SquadId; readonly name: string };
  readonly week: WeekStart;
  readonly failures: Failures;
}): PushNotification {
  return {
    alert: {
      key: 'push.weeklyAwards.stuck',
      args: [squad.name, String(failures.count), failures.lastError ?? '-'],
    },
    category: 'weeklyAwardsStuck',
    thread: 'weekly-awards-stuck',
    collapseId: `weekly-awards-stuck-${squad.id}-${week}`,
    interruption: 'active',
    event: { squad: squad.id, weekStart: week },
  };
}

/** How many squads' awards are written at once. */
const AT_ONCE = 4;

/**
 * Gives the latest week's awards (Sunday 8pm Eastern) to every squad that checked in before
 * then, and tells each winner once. Meant to run every hour: a squad whose awards couldn't be
 * written is tried again on the next run, through the following week too, and a squad already
 * done is only checked. Check-ins made after the awards' moment still count for the week, only
 * not for its awards.
 */
export async function giveWeeklyAwards(deps: WeeklyAwardsDependencies): Promise<WeeklyAwardsRun> {
  const latest = latestAwardedWeek(deps.clock());
  const previous = WeekStart.parse(
    new Date(Date.parse(latest) - 7 * 86_400_000).toISOString().slice(0, 10),
  );
  const runs = [await giveWeek(deps, previous), await giveWeek(deps, latest)];
  const total = (key: 'squads' | 'given' | 'failed' | 'told') =>
    runs.reduce((sum, run) => sum + run[key], 0);
  return {
    weeks: [previous, latest],
    squads: total('squads'),
    given: total('given'),
    failed: total('failed'),
    told: total('told'),
  };
}

/** One week's awards for every squad that checked in before them, as `giveWeeklyAwards`. */
async function giveWeek(
  deps: WeeklyAwardsDependencies,
  week: WeekStart,
): Promise<Omit<WeeklyAwardsRun, 'weeks'>> {
  const before = awardsTimeOf(week);
  const squads = await deps.checkIns.squadsCheckedInto({
    weekStart: CheckInWeek.parse(week),
    before,
  });
  let given = 0;
  let failed = 0;
  let told = 0;
  for (let start = 0; start < squads.length; start += AT_ONCE) {
    await Promise.all(
      squads.slice(start, start + AT_ONCE).map(async (squad) => {
        try {
          if ((await deps.awards.find({ squad, weekStart: week }))?.status !== 'given') {
            const { members, pages } = await memberWeeks(deps, { squad, week, before });
            await deps.awards.give({ squad, weekStart: week, members, pages });
            given += 1;
          }
          const winners = await deps.awards.claimWinners({ squad, weekStart: week });
          if (winners.length > 0) {
            const outcome = await deps.push.notifyMembers({
              members: winners.map((member) => PushMember.parse(member)),
              notification: awardsReadyNotification(squad, week),
            });
            told += winners.length;
            if (outcome.failures.length > 0) {
              deps.log.warn('some winners’ phones refused the awards push', {
                squad,
                failures: outcome.failures.length,
              });
            }
          }
        } catch (error) {
          failed += 1;
          deps.log.error('a squad’s weekly awards failed; the next run tries again', {
            squad,
            week,
            error,
          });
        }
      }),
    );
  }
  return { squads: squads.length, given, failed, told };
}

/** The pages of the story, in the order they play: the awards first, the ending last. */
export type StoryPage = 'podium' | 'titles' | MiddlePage | 'ending';

/** A squad's week story as one of its members reads it: the awards, once they are due. */
export interface SquadStory {
  readonly squad: { readonly id: SquadId; readonly name: string };
  /**
   * `pending`: due, but the titles aren't written yet (the run hasn't reached the squad, or the
   * model failed). Only the titles wait: the pages without AI are there either way, without
   * the AI's words and moves.
   */
  readonly status: 'ready' | 'pending';
  /** Members still in the squad, in the order they joined; empty until ready, or when nobody checked in. */
  readonly members: readonly MemberAwards[];
  /** The AI's page order, once ready. */
  readonly order?: readonly StoryPage[];
  readonly podium?: {
    readonly champion: string;
    readonly sides: readonly string[];
    readonly speech?: string;
    readonly championMove?: AwardMove;
    readonly sideMove?: AwardMove;
  };
  /** The viewer's week, when they checked in before the awards. */
  readonly myWeek?: {
    readonly plan: number;
    readonly days: readonly StoryDay[];
    readonly line?: string;
    readonly healthyMeals: number;
    readonly cheatMeals: number;
    readonly reactionsReceived: number;
  };
  /** The viewer's check-in with the most reactions before the awards, when one had any. */
  readonly hottest?: TopCheckIn & Partial<HottestWords>;
  readonly meals?: {
    readonly healthy: number;
    readonly cheat: number;
    readonly eaters: readonly { readonly member: string; readonly more: 'healthy' | 'cheat' }[];
    readonly line?: string;
  };
  readonly bestDisclaimer?: {
    readonly checkIn: string;
    readonly author: string;
    readonly text: string;
    readonly reactions: number;
    readonly authorMove?: AwardMove;
    readonly squadMove?: AwardMove;
  };
  readonly ending?: {
    readonly done: number;
    readonly plan: number;
    readonly headline?: string;
    readonly line?: string;
    readonly move?: AwardMove;
  };
}

/**
 * A squad's week story for one of its members. Throws `WeekStoryNotReadyError` before the
 * week's awards (Sunday 8pm Eastern), `SquadNotJoinedError` for anyone not in the squad. The
 * pages' facts are read from the week as the awards saw it, so the AI's words still fit them.
 */
export async function squadStory(
  deps: Pick<WeeklyAwardsDependencies, 'checkIns' | 'squads' | 'awards' | 'clock'>,
  {
    viewer,
    squad,
    weekStart,
  }: { readonly viewer: string; readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<SquadStory> {
  const found = await dueSquad(deps, { viewer, squad, weekStart });
  const [state, week] = await Promise.all([
    deps.awards.find({ squad, weekStart }),
    weekBeforeAwards(deps, { squad, weekStart }),
  ]);
  const { pages } = week;
  const mine = week.members.find(({ member }) => member === viewer)?.checkIns ?? [];
  const page = pages.members.find(({ member }) => member === viewer);
  const facts = {
    squad: { id: squad, name: found.name },
    ...(pages.podium === undefined ? {} : { podium: pages.podium }),
    ...(page?.checkedIn === true
      ? {
          myWeek: {
            plan: page.plannedDays,
            days: page.days,
            healthyMeals: page.healthyMeals,
            cheatMeals: page.cheatMeals,
            reactionsReceived: page.reactionsReceived,
          },
        }
      : {}),
    ...(pages.meals === undefined ? {} : { meals: pages.meals }),
    ...(pages.bestDisclaimer === undefined ? {} : { bestDisclaimer: pages.bestDisclaimer }),
    ...(pages.ending === undefined ? {} : { ending: pages.ending }),
  };

  if (state?.status !== 'given') {
    // Not written yet: the hottest check-in as the awards will see it, from the week so far.
    const anyone = week.members.some(({ checkIns }) => checkIns.length > 0);
    const hottest = topCheckInOf(mine.map((record) => weekCheckIn(record, week.reactions)));
    return {
      ...facts,
      status: anyone ? 'pending' : 'ready',
      members: [],
      ...(hottest === undefined ? {} : { hottest }),
    };
  }

  // Members who left take their awards with them, as their check-ins leave the feed.
  const inSquad = new Set<string>(found.members.map(({ member }) => member));
  const members = state.awards.members.filter(({ member }) => inSquad.has(member));
  const own = members.find(({ member }) => member === MemberId.parse(viewer));
  const words = state.awards.story;
  // The AI's words only on the page they were written for: a member leaving or a later
  // reaction can change the champion, the best note or whether the squad hit its plan.
  const podiumWords =
    words?.podium?.champion === facts.podium?.champion ? words?.podium : undefined;
  const noteWords =
    words?.bestDisclaimer?.checkIn === facts.bestDisclaimer?.checkIn
      ? words?.bestDisclaimer
      : undefined;
  const endingWords =
    facts.ending !== undefined && words?.ending?.hit === facts.ending.done >= facts.ending.plan
      ? words.ending
      : undefined;
  const story: SquadStory = {
    ...facts,
    status: 'ready',
    members,
    ...(facts.podium === undefined || podiumWords === undefined
      ? {}
      : {
          podium: {
            ...facts.podium,
            speech: podiumWords.speech,
            championMove: podiumWords.championMove,
            sideMove: podiumWords.sideMove,
          },
        }),
    ...(facts.myWeek === undefined
      ? {}
      : { myWeek: { ...facts.myWeek, ...(own?.line === undefined ? {} : { line: own.line }) } }),
    ...(own?.topCheckIn === undefined ? {} : { hottest: { ...own.topCheckIn, ...own.hottest } }),
    ...(facts.meals === undefined ? {} : { meals: { ...facts.meals, ...words?.meals } }),
    ...(facts.bestDisclaimer === undefined || noteWords === undefined
      ? {}
      : {
          bestDisclaimer: {
            ...facts.bestDisclaimer,
            authorMove: noteWords.authorMove,
            squadMove: noteWords.squadMove,
          },
        }),
    ...(facts.ending === undefined || endingWords === undefined
      ? {}
      : {
          ending: {
            ...facts.ending,
            headline: endingWords.headline,
            line: endingWords.line,
            move: endingWords.move,
          },
        }),
  };
  if (words === undefined) return story;
  // The AI's order, less the pages this reader's story doesn't have.
  const has: Record<StoryPage, boolean> = {
    podium: story.podium !== undefined,
    titles: members.length > 0,
    myWeek: story.myWeek !== undefined,
    hottest: story.hottest !== undefined,
    meals: story.meals !== undefined,
    bestDisclaimer: story.bestDisclaimer !== undefined,
    ending: story.ending !== undefined,
  };
  const order: StoryPage[] = ['podium', 'titles', ...words.order, 'ending'];
  return { ...story, order: order.filter((page) => has[page]) };
}

/**
 * A member nudging the organisers (催一下主办方) about a story whose titles haven't come: the
 * first nudge since the squad-week's last failed try (or before its first) tells every admin,
 * with the failed tries and why; other nudges, nudges once the titles are written, and nudges
 * for a squad where nobody checked in (no titles to wait for) do nothing. Throws as
 * `squadStory` does.
 */
export async function nudgeOrganisers(
  deps: Pick<
    WeeklyAwardsDependencies,
    'checkIns' | 'squads' | 'awards' | 'push' | 'admins' | 'clock' | 'log'
  >,
  {
    viewer,
    squad,
    weekStart,
  }: { readonly viewer: string; readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<void> {
  const found = await dueSquad(deps, { viewer, squad, weekStart });
  if (!(await anyoneCheckedIn(deps, { squad, weekStart }))) return;
  const failures = await deps.awards.claimNudge({ squad, weekStart });
  if (failures === undefined) return;
  const admins = await deps.admins.list();
  const outcome = await deps.push.notifyMembers({
    members: admins.map((admin) => PushMember.parse(admin)),
    notification: awardsStuckNotification({
      squad: { id: squad, name: found.name },
      week: weekStart,
      failures,
    }),
  });
  deps.log.warn('a member nudged about weekly awards that haven’t come', {
    squad,
    week: weekStart,
    failures: failures.count,
    lastError: failures.lastError,
    admins: admins.length,
    refused: outcome.failures.length,
  });
}

/** The squad's week as its awards read it: the check-ins made before them. */
function weekBeforeAwards(
  deps: Pick<WeeklyAwardsDependencies, 'checkIns'>,
  { squad, weekStart }: { readonly squad: SquadId; readonly weekStart: WeekStart },
) {
  return deps.checkIns.squadWeekCheckIns({
    squad: CheckInSquad.parse(squad),
    weekStart: CheckInWeek.parse(weekStart),
    before: awardsTimeOf(weekStart),
  });
}

/** Whether anyone in the squad checked in before the week's awards, so it has any to wait for. */
async function anyoneCheckedIn(
  deps: Pick<WeeklyAwardsDependencies, 'checkIns'>,
  week: { readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<boolean> {
  const { members } = await weekBeforeAwards(deps, week);
  return members.some(({ checkIns }) => checkIns.length > 0);
}

/** The squad, for one of its members, once its week's awards are due. */
async function dueSquad(
  deps: Pick<WeeklyAwardsDependencies, 'squads' | 'clock'>,
  {
    viewer,
    squad,
    weekStart,
  }: { readonly viewer: string; readonly squad: SquadId; readonly weekStart: WeekStart },
) {
  const found = await deps.squads.find({
    squad: SquadsSquad.parse(squad),
    viewer: SquadsMember.parse(viewer),
  });
  if (deps.clock() < awardsTimeOf(weekStart)) throw new WeekStoryNotReadyError(weekStart);
  return found;
}

/**
 * Everyone in the squad with their check-ins before the awards, as the awards read them, and
 * the squad's pages they write on.
 */
async function memberWeeks(
  deps: Pick<WeeklyAwardsDependencies, 'checkIns' | 'members'>,
  {
    squad,
    week,
    before,
  }: { readonly squad: SquadId; readonly week: WeekStart; readonly before: Date },
): Promise<{ readonly members: MemberWeek[]; readonly pages: SquadPages }> {
  const squadWeek = await deps.checkIns.squadWeekCheckIns({
    squad: CheckInSquad.parse(squad),
    weekStart: CheckInWeek.parse(week),
    before,
  });
  const { podium, meals, bestDisclaimer, ending } = squadWeek.pages;
  const members = await Promise.all(
    squadWeek.members.map(async ({ member, checkIns }) => {
      const profile = await deps.members.findProfile(member);
      const page = squadWeek.pages.members.find((each) => each.member === member);
      return {
        member: MemberId.parse(member),
        // A member who checked in has saved a time zone; UTC only for one who never did.
        timeZone: profile?.timeZone ?? 'UTC',
        plannedDays: page?.plannedDays ?? 0,
        trainedDays: page?.trainedDays ?? 0,
        checkIns: checkIns.map((record) => weekCheckIn(record, squadWeek.reactions)),
      };
    }),
  );
  return {
    members,
    pages: {
      ...(podium === undefined
        ? {}
        : {
            podium: {
              champion: MemberId.parse(podium.champion),
              sides: podium.sides.map((side) => MemberId.parse(side)),
            },
          }),
      ...(meals === undefined ? {} : { meals: { healthy: meals.healthy, cheat: meals.cheat } }),
      ...(bestDisclaimer === undefined
        ? {}
        : {
            bestDisclaimer: {
              checkIn: bestDisclaimer.checkIn,
              author: MemberId.parse(bestDisclaimer.author),
              text: bestDisclaimer.text,
            },
          }),
      ...(ending === undefined ? {} : { ending }),
    },
  };
}

function weekCheckIn(
  record: CheckInRecord,
  reactions: SquadWeekCheckIns['reactions'],
): WeekCheckIn {
  const counts: Record<string, number> = {};
  for (const { emoji } of reactions.get(record.id) ?? []) counts[emoji] = (counts[emoji] ?? 0) + 1;
  const base = {
    id: record.id,
    day: record.day,
    createdAt: record.createdAt,
    kind: record.kind,
    photos: photosOf(record).map(({ path }) => path),
    reactions: counts,
  };
  switch (record.kind) {
    case 'trained':
      return {
        ...base,
        sport: record.training.customSport ?? record.training.sport,
        caption: record.training.caption,
      };
    case 'healthyMeal':
    case 'cheatMeal':
      return { ...base, caption: record.meal.caption };
    case 'disclaimer':
      return { ...base, text: record.disclaimer.text };
  }
}
