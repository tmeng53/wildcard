import {
  CheckInId,
  MemberId as CheckInMember,
  SquadId as CheckInSquad,
  WeekStart as CheckInWeek,
  photosOf,
  type CheckInRecord,
  type CheckIns,
  type SquadWeekCheckIns,
} from '@wildcard/check-ins';
import type { Admins } from '@wildcard/admins';
import type { Members } from '@wildcard/members';
import { MemberId as PushMember, type Push, type PushNotification } from '@wildcard/push';
import {
  MemberId as SquadsMember,
  SceneWeek,
  SquadId as SquadsSquad,
  type Squads,
} from '@wildcard/squads';
import {
  MemberId,
  awardsTimeOf,
  latestAwardedWeek,
  topCheckInOf,
  type Failures,
  type MemberAwards,
  type MemberWeek,
  type SquadId,
  type StoryMember,
  type WeekCheckIn,
  WeekStart,
  type WeekStory,
  type WeeklyAwards,
  WeekStoryNotReadyError,
} from '@wildcard/weekly-awards';

import type { Log } from '../log.js';

// The weekly awards and the frozen 战报 across modules: who was in the squad and its scene from
// squads, the week's check-ins and pages from check-ins, members' clocks and characters from
// members, the awards and the stored 战报 from weekly-awards, the winners' push from push, and
// the admins a nudge tells from admins.

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
          // The 战报 freezes first, so the awards are written for the same members and week.
          const story = await frozenStory(deps, { squad, weekStart: week });
          if ((await deps.awards.find({ squad, weekStart: week }))?.status !== 'given') {
            const members = await memberWeeks(deps, {
              squad,
              week,
              before,
              members: story.members.map(({ member }) => member),
            });
            await deps.awards.give({ squad, weekStart: week, members });
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

/** A squad's 战报 as one of its members reads it: frozen at the week's awards. */
export interface SquadStory {
  /** The squad's id, and its name that week. */
  readonly squad: { readonly id: SquadId; readonly name: string };
  /** The scene the squad trained on that week. */
  readonly scene: string;
  /**
   * `pending`: due, but the titles aren't written yet (the run hasn't reached the squad, or the
   * model failed). Only the titles wait: every other page is frozen either way.
   */
  readonly status: 'ready' | 'pending';
  /** Everyone in the squad at the awards, in the order they joined, less accounts deleted since. */
  readonly members: readonly StoryMember[];
  /** The titles, in the members' order: empty until ready, or when nobody checked in. */
  readonly titles: readonly MemberAwards[];
  /** The crown winner in the middle, up to 2 others who finished their plan beside. */
  readonly podium?: { readonly champion: string; readonly sides: readonly string[] };
  /** The squad's meals; who ate more of what is in each member's part. */
  readonly meals?: { readonly healthy: number; readonly cheat: number };
  /** The squad's days trained against its plans; only when someone trained. */
  readonly ending?: { readonly done: number; readonly plan: number };
  /** The squad's best 请假条 and who wrote it, while it is still posted. */
  readonly bestDisclaimer?: {
    readonly author: string;
    readonly checkIn: string;
    readonly text: string;
    readonly reactions: number;
  };
  /** The reader's part, when they were in the squad at the awards; its hottest only while posted. */
  readonly mine?: StoryMember;
}

/**
 * A squad's 战报 for one of its members: the one frozen at the week's awards, frozen now if no
 * run has yet. Nothing that happened since changes it, except that a deleted account or post
 * takes its own words and photos with it. Throws `WeekStoryNotReadyError` before the week's
 * awards (Sunday 8pm Eastern), `SquadNotJoinedError` for anyone not in the squad now.
 */
export async function squadStory(
  deps: Pick<WeeklyAwardsDependencies, 'checkIns' | 'squads' | 'members' | 'awards' | 'clock'>,
  {
    viewer,
    squad,
    weekStart,
  }: { readonly viewer: string; readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<SquadStory> {
  await dueSquad(deps, { viewer, squad, weekStart });
  const [frozen, state] = await Promise.all([
    frozenStory(deps, { squad, weekStart }),
    deps.awards.find({ squad, weekStart }),
  ]);
  const { story, members } = frozen;
  const ids = new Set<string>(members.map(({ member }) => member));
  const mine = members.find(({ member }) => member === viewer);
  const best = members.flatMap(({ member, bestDisclaimer }) =>
    bestDisclaimer === undefined ? [] : [{ author: member, ...bestDisclaimer }],
  )[0];
  const posted = await deps.checkIns.stillPosted(
    [mine?.hottest?.checkIn, best?.checkIn].flatMap((id) =>
      id === undefined ? [] : [CheckInId.parse(id)],
    ),
  );
  const isPosted = (id: string) => posted.has(CheckInId.parse(id));
  // Someone on the podium whose account was deleted since leaves it; a side steps up.
  const podium =
    story.podium && [story.podium.champion, ...story.podium.sides].filter((id) => ids.has(id));
  const [champion, ...sides] = podium ?? [];
  const titles =
    state?.status === 'given' ? state.awards.members.filter(({ member }) => ids.has(member)) : [];
  const anyone = members.some(({ checkedIn }) => checkedIn);
  return {
    squad: { id: squad, name: story.name },
    scene: story.scene,
    status: state?.status === 'given' || !anyone ? 'ready' : 'pending',
    members,
    titles,
    ...(champion === undefined ? {} : { podium: { champion, sides } }),
    ...(story.meals === undefined ? {} : { meals: story.meals }),
    ...(story.ending === undefined ? {} : { ending: story.ending }),
    ...(best === undefined || !isPosted(best.checkIn) ? {} : { bestDisclaimer: best }),
    ...(mine === undefined ? {} : { mine: withPosted(mine, isPosted) }),
  };
}

/** A member's part with their hottest check-in only while it is still posted. */
function withPosted(member: StoryMember, isPosted: (id: string) => boolean): StoryMember {
  const { hottest, ...rest } = member;
  return hottest === undefined || !isPosted(hottest.checkIn) ? rest : member;
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
    'checkIns' | 'squads' | 'members' | 'awards' | 'push' | 'admins' | 'clock' | 'log'
  >,
  {
    viewer,
    squad,
    weekStart,
  }: { readonly viewer: string; readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<void> {
  const found = await dueSquad(deps, { viewer, squad, weekStart });
  const { members } = await frozenStory(deps, { squad, weekStart });
  if (!members.some(({ checkedIn }) => checkedIn)) return;
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

/**
 * A squad's 战报 for the week, frozen at its awards (Sunday 8pm Eastern): the stored one, else
 * frozen now from the squad as it stood then: who was in it, that week's scene, and their
 * check-ins and reactions made before then. Members' characters are as they are when it
 * freezes, which the hourly awards run does within the hour for every squad that checked in.
 */
async function frozenStory(
  deps: Pick<WeeklyAwardsDependencies, 'checkIns' | 'squads' | 'members' | 'awards'>,
  { squad, weekStart }: { readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<WeekStory> {
  const stored = await deps.awards.story({ squad, weekStart });
  if (stored !== undefined) return stored;
  const before = awardsTimeOf(weekStart);
  const then = await deps.squads.squadAt({
    squad: SquadsSquad.parse(squad),
    week: SceneWeek.parse(weekStart),
    moment: before,
  });
  if (then === undefined) throw new Error(`Squad ${squad} is gone`);
  const week = await deps.checkIns.squadWeekCheckIns({
    squad: CheckInSquad.parse(squad),
    weekStart: CheckInWeek.parse(weekStart),
    before,
    members: then.members.map((member) => CheckInMember.parse(member)),
  });
  const profiles = await Promise.all(
    week.members.map(({ member }) => deps.members.findProfile(member)),
  );
  const { pages } = week;
  return deps.awards.freezeStory({
    squad,
    weekStart,
    story: {
      version: 1,
      name: then.name,
      scene: then.scene,
      ...(pages.podium === undefined
        ? {}
        : { podium: { champion: pages.podium.champion, sides: [...pages.podium.sides] } }),
      ...(pages.meals === undefined
        ? {}
        : { meals: { healthy: pages.meals.healthy, cheat: pages.meals.cheat } }),
      ...(pages.ending === undefined ? {} : { ending: pages.ending }),
    },
    members: week.members.map(({ member, checkIns }, index): StoryMember => {
      const page = pages.members[index];
      if (page?.member !== member) throw new Error('The 战报’s pages don’t match its members');
      const hottest = topCheckInOf(checkIns.map((record) => weekCheckIn(record, week.reactions)));
      const best = pages.bestDisclaimer;
      return {
        member: MemberId.parse(member),
        version: 1,
        character: profiles[index]?.character ?? null,
        checkedIn: page.checkedIn,
        plannedDays: page.plannedDays,
        trainedDays: page.trainedDays,
        days: page.days.map(({ day, kind, sport }) => ({
          day,
          kind,
          ...(sport === undefined ? {} : { sport }),
        })),
        healthyMeals: page.healthyMeals,
        cheatMeals: page.cheatMeals,
        reactionsReceived: page.reactionsReceived,
        ...(hottest === undefined ? {} : { hottest }),
        ...(best?.author === member
          ? {
              bestDisclaimer: { checkIn: best.checkIn, text: best.text, reactions: best.reactions },
            }
          : {}),
      };
    }),
  });
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

/** These members with their check-ins before the awards, as the awards read them. */
async function memberWeeks(
  deps: Pick<WeeklyAwardsDependencies, 'checkIns' | 'members'>,
  {
    squad,
    week,
    before,
    members,
  }: {
    readonly squad: SquadId;
    readonly week: WeekStart;
    readonly before: Date;
    readonly members: readonly string[];
  },
): Promise<MemberWeek[]> {
  const squadWeek = await deps.checkIns.squadWeekCheckIns({
    squad: CheckInSquad.parse(squad),
    weekStart: CheckInWeek.parse(week),
    before,
    members: members.map((member) => CheckInMember.parse(member)),
  });
  return Promise.all(
    squadWeek.members.map(async ({ member, checkIns }) => {
      const profile = await deps.members.findProfile(member);
      return {
        member: MemberId.parse(member),
        // A member who checked in has saved a time zone; UTC only for one who never did.
        timeZone: profile?.timeZone ?? 'UTC',
        checkIns: checkIns.map((record) => weekCheckIn(record, squadWeek.reactions)),
      };
    }),
  );
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
