import {
  CheckInId,
  MemberId as CheckInMember,
  SquadId as CheckInSquad,
  WeekStart as CheckInWeek,
  photosOf,
  podiumOf,
  type Podium,
  type CheckInRecord,
  type CheckIns,
  type SquadWeekCheckIns,
} from '@wildcard/check-ins';
import type { Admins } from '@wildcard/admins';
import type { Members } from '@wildcard/members';
import { MemberId as NoticeMember, SquadId as NoticeSquad, type Notices } from '@wildcard/notices';
import { MemberId as PushMember, type Push, type PushNotification } from '@wildcard/push';
import {
  MemberId as SquadsMember,
  SceneWeek,
  SquadId as SquadsSquad,
  type Squads,
} from '@wildcard/squads';
import type { Scenes } from '@wildcard/scenes';
import type { WeekStart } from '@wildcard/weekly-awards';
import {
  MemberId,
  awardsTimeOf,
  topCheckInOf,
  type AwardsState,
  type Failures,
  type MemberAwards,
  type MemberWeek,
  SquadId,
  type StoryMember,
  type WeekCheckIn,
  type WeekStory,
  type WeeklyAwards,
  WeekStoryNotReadyError,
  weeksMaybeAwarded,
} from '@wildcard/weekly-awards';

import type { Log } from '../log.js';
import { pushAlert } from '../push-copy.js';
import { squadsAwardedIn } from './awarded-squads.js';
import { noticeAlert } from './daily-progress-push.js';
import { squadLanguages } from './squad-language.js';

// The weekly awards and the frozen 战报 across modules: who was in the squad and its scene from
// squads, the week's check-ins and pages from check-ins, members' clocks and characters from
// members, the awards and the stored 战报 from weekly-awards, the squad's push from push, and
// the admins a nudge tells from admins. Each squad's week ends Sunday 8pm on its own clock, its
// time zone (小队时区).

export interface WeeklyAwardsDependencies {
  readonly checkIns: CheckIns;
  readonly members: Members;
  readonly squads: Squads;
  /** Which scenes were open in a week: a squad on one that closed trained in the gym. */
  readonly scenes: Pick<Scenes, 'openOn'>;
  readonly awards: WeeklyAwards;
  readonly push: Push;
  /** Where each push sent is kept for the member's 通知. */
  readonly notices: Notices;
  readonly admins: Pick<Admins, 'list'>;
  readonly clock: () => Date;
  readonly log: Log;
}

/** What a run did, squad by squad. */
export interface WeeklyAwardsRun {
  /**
   * The weeks it looked at: the latest due in any zone, and the one before for squads still
   * failing. A squad's own week is due at its own Sunday 8pm.
   */
  readonly weeks: readonly WeekStart[];
  /** Squads with a check-in for the week made before the awards. */
  readonly squads: number;
  /** Squads whose awards this run wrote. */
  readonly given: number;
  /** Squads whose awards couldn't be written; the next run tries again. */
  readonly failed: number;
  /** Members this run told their squad's 战报 is ready, each once a squad. */
  readonly told: number;
}

/**
 * The squad's push when its 战报 is ready, to everyone in it. It says only that the awards are
 * in, never who won what, so opening the story is the surprise. A later one for the same week replaces it.
 */
export function awardsReadyNotification(squad: SquadId, week: WeekStart): PushNotification {
  return {
    alert: pushAlert('push.weeklyAwards.ready', []),
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
    alert: pushAlert('push.weeklyAwards.stuck', [
      squad.name,
      String(failures.count),
      failures.lastError ?? '-',
    ]),
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
 * Gives the latest week's awards (Sunday 8pm on each squad's clock) to every squad that checked
 * in before then, and tells everyone in the squad once. Meant to run every hour: a squad whose
 * awards couldn't be written is tried again on the next run, through the following week too, and
 * a squad already done is only checked. Check-ins made after the awards' moment still count for
 * the week, only not for its awards.
 */
export async function giveWeeklyAwards(deps: WeeklyAwardsDependencies): Promise<WeeklyAwardsRun> {
  const weeks = weeksMaybeAwarded(deps.clock());
  const runs: Omit<WeeklyAwardsRun, 'weeks'>[] = [];
  for (const week of weeks) runs.push(await giveWeek(deps, week));
  const total = (key: 'squads' | 'given' | 'failed' | 'told') =>
    runs.reduce((sum, run) => sum + run[key], 0);
  return {
    weeks,
    squads: total('squads'),
    given: total('given'),
    failed: total('failed'),
    told: total('told'),
  };
}

/** When the squad's awards of the week are given: its Sunday 8pm in its zone that week. */
async function awardsTimeFor(
  deps: Pick<WeeklyAwardsDependencies, 'squads'>,
  { squad, weekStart }: { readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<Date> {
  const id = SquadsSquad.parse(squad);
  const zone = (await deps.squads.timeZonesFor([id], weekStart)).get(id);
  if (zone === undefined) throw new Error(`No time zone for squad ${squad}`);
  return awardsTimeOf(weekStart, zone);
}

/** One week's awards for every squad that checked in before them, as `giveWeeklyAwards`. */
async function giveWeek(
  deps: WeeklyAwardsDependencies,
  week: WeekStart,
): Promise<Omit<WeeklyAwardsRun, 'weeks'>> {
  const due = await squadsAwardedIn(
    { ...deps, waiting: (weekStart) => deps.awards.storiesWaiting({ weekStart }) },
    week,
  );
  const squads = [...due.keys()].map((squad) => SquadId.parse(squad));
  let given = 0;
  let failed = 0;
  let told = 0;
  for (let start = 0; start < squads.length; start += AT_ONCE) {
    await Promise.all(
      squads.slice(start, start + AT_ONCE).map(async (squad) => {
        try {
          const before =
            due.get(squad)?.at ?? (await awardsTimeFor(deps, { squad, weekStart: week }));
          // The 战报 freezes first, so the awards are written for the same members and week.
          const story = await frozenStory(deps, { squad, weekStart: week });
          if ((await deps.awards.find({ squad, weekStart: week }))?.status !== 'given') {
            const members = await memberWeeks(deps, {
              squad,
              week,
              before,
              members: story.members.map(({ member }) => member),
            });
            const { squad: language } = await squadLanguages(deps, {
              squad,
              members: story.members.map(({ member }) => member),
            });
            await deps.awards.give({
              squad,
              weekStart: week,
              members,
              ending: await squadEnding(deps, story),
              language,
            });
            given += 1;
          }
          if (await deps.awards.claimReadyPush({ squad, weekStart: week })) {
            // The whole squad as the 战报 froze it, less anyone who has left since.
            const now = new Set<string>(await deps.squads.membersOf(SquadsSquad.parse(squad)));
            const members = story.members
              .map(({ member }) => member)
              .filter((member) => now.has(member));
            const notification = awardsReadyNotification(squad, week);
            // Kept in each one's 通知 too, whether or not it reaches a phone. Never fails the run.
            await deps.notices
              .tell(
                members.map((member) => ({
                  member: NoticeMember.parse(member),
                  squad: NoticeSquad.parse(squad),
                  kind: 'weeklyAwards' as const,
                  subject: {
                    version: 1 as const,
                    alert: noticeAlert(notification),
                    weekStart: week,
                  },
                })),
              )
              .catch((error: unknown) => {
                deps.log.warn('awards push not kept in notices', { squad, error });
              });
            const outcome = await deps.push.notifyMembers({
              members: members.map((member) => PushMember.parse(member)),
              notification,
            });
            told += members.length;
            if (outcome.failures.length > 0) {
              deps.log.warn('some members’ phones refused the awards push', {
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
  /**
   * Whether a try at the titles has failed since the week's awards: a `pending` story that isn't
   * stuck is only waiting for the hourly run to reach the squad.
   */
  readonly stuck: boolean;
  /** Everyone in the squad at the awards, in the order they joined, less accounts deleted since. */
  readonly members: readonly StoryMember[];
  /** The titles, in the members' order: empty until ready, or when nobody checked in. */
  readonly titles: readonly MemberAwards[];
  /** The top 3 by days trained, the crown winner in the middle, and who finished their plan. */
  readonly podium?: Podium<string>;
  /** The squad's meals; who ate more of what is in each member's part. */
  readonly meals?: { readonly healthy: number; readonly cheat: number };
  /**
   * The squad's 训练 against its weekly goal (人均 N 次 times its members), only when
   * someone trained, with the model's headline and line for them once the awards are written.
   */
  readonly ending?: {
    readonly done: number;
    readonly plan: number;
    readonly headline?: string;
    readonly line?: string;
  };
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
 * The squad's 训练 against its weekly goal that week (小队每周目标: 人均 N 次 times the
 * members in its 战报), as the squad's ring on 今天 counts them, or none when nobody trained. The
 * goal is read, not taken from the frozen story: weeks frozen before the goal came stored the
 * members' plans added up, and a week's goal never changes once the week has begun.
 */
async function squadEnding(
  deps: Pick<WeeklyAwardsDependencies, 'squads'>,
  story: WeekStory,
): Promise<{ readonly done: number; readonly plan: number } | undefined> {
  const { ending } = story.story;
  if (ending === undefined) return undefined;
  const days = await deps.squads.daysPerMember(SquadsSquad.parse(story.squad), story.weekStart);
  return { done: ending.done, plan: days * story.members.length };
}

/** The squad's 训练 against its goal, with the model's words for them once they are written. */
function endingOf(
  ending: { readonly done: number; readonly plan: number },
  state: AwardsState | undefined,
): NonNullable<SquadStory['ending']> {
  const words = state?.status === 'given' ? state.awards.ending : undefined;
  return words === undefined
    ? { done: ending.done, plan: ending.plan }
    : { done: ending.done, plan: ending.plan, headline: words.headline, line: words.line };
}

/**
 * A squad's 战报 for one of its members: the one frozen at the week's awards, frozen now if no
 * run has yet. Nothing that happened since changes it, except that a deleted account or post
 * takes its own words and photos with it. Throws `WeekStoryNotReadyError` before the week's
 * awards (Sunday 8pm on the squad's clock), `SquadNotJoinedError` for anyone not in the squad now.
 */
export async function squadStory(
  deps: Pick<
    WeeklyAwardsDependencies,
    'checkIns' | 'squads' | 'scenes' | 'members' | 'awards' | 'clock'
  >,
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
  const frozenMine = members.find(({ member }) => member === viewer);
  const mine = frozenMine && (await withPhotosStillPosted(deps, frozenMine));
  const best = members.flatMap(({ member, bestDisclaimer }) =>
    bestDisclaimer === undefined ? [] : [{ author: member, ...bestDisclaimer }],
  )[0];
  // From the members' frozen days, less accounts deleted since: someone else steps up.
  const podium = podiumOf(members);
  const titles =
    state?.status === 'given' ? state.awards.members.filter(({ member }) => ids.has(member)) : [];
  const anyone = members.some(({ checkedIn }) => checkedIn);
  return {
    squad: { id: squad, name: story.name },
    scene: story.scene,
    status: state?.status === 'given' || !anyone ? 'ready' : 'pending',
    stuck: anyone && state?.status === 'failing',
    members,
    titles,
    ...(podium === undefined ? {} : { podium }),
    ...(story.meals === undefined ? {} : { meals: story.meals }),
    ...(await squadEnding(deps, frozen).then((ending) =>
      ending === undefined ? {} : { ending: endingOf(ending, state) },
    )),
    ...(best === undefined ? {} : { bestDisclaimer: best }),
    ...(mine === undefined ? {} : { mine }),
  };
}

/**
 * The weeks a squad has a 战报 for, the latest first, for one of its members (往期战报 on the
 * squad's page). The latest week whose awards are due on the squad's clock is frozen first if no
 * run has yet, so it is listed the moment it comes out. A week nobody checked in has none. Throws
 * `SquadNotJoinedError` for anyone not in the squad now.
 */
export async function squadStoryWeeks(
  deps: Pick<
    WeeklyAwardsDependencies,
    'checkIns' | 'squads' | 'scenes' | 'members' | 'awards' | 'clock'
  >,
  { viewer, squad }: { readonly viewer: string; readonly squad: SquadId },
): Promise<WeekStart[]> {
  await deps.squads.find({ squad: SquadsSquad.parse(squad), viewer: SquadsMember.parse(viewer) });
  const now = deps.clock();
  for (const week of weeksMaybeAwarded(now).reverse()) {
    if ((await awardsTimeFor(deps, { squad, weekStart: week })) > now) continue;
    await frozenStory(deps, { squad, weekStart: week });
    break;
  }
  return deps.awards.storyWeeks({ squad });
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
    'checkIns' | 'squads' | 'scenes' | 'members' | 'awards' | 'push' | 'admins' | 'clock' | 'log'
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
 * A squad's 战报 for the week, frozen at its awards (Sunday 8pm on its clock): the stored one, else
 * frozen now from the squad as it stood then: who was in it, that week's scene, and their
 * check-ins and reactions made before then. Members' characters and the squad's name are as
 * they are when it freezes, which the hourly awards run does within the hour for every squad
 * that checked in. A week nobody checked in is never stored.
 */
async function frozenStory(
  deps: Pick<WeeklyAwardsDependencies, 'checkIns' | 'squads' | 'scenes' | 'members' | 'awards'>,
  { squad, weekStart }: { readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<WeekStory> {
  const stored = await deps.awards.story({ squad, weekStart });
  if (stored !== undefined) return stored;
  const before = await awardsTimeFor(deps, { squad, weekStart });
  const then = await deps.squads.squadAt({
    squad: SquadsSquad.parse(squad),
    week: SceneWeek.parse(weekStart),
    moment: before,
    open: await deps.scenes.openOn(weekStart),
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
  const story: WeekStory = {
    squad,
    weekStart,
    story: {
      version: 1,
      name: then.name,
      scene: then.scene,
      ...(pages.meals === undefined
        ? {}
        : { meals: { healthy: pages.meals.healthy, cheat: pages.meals.cheat } }),
      ...(pages.ending === undefined ? {} : { ending: pages.ending }),
    },
    members: week.members.map(({ member, checkIns }, index): StoryMember => {
      const page = pages.members[index];
      if (page?.member !== member) throw new Error('The 战报’s pages don’t match its members');
      const hottest = topCheckInOf(checkIns.map((record) => weekCheckIn(record, week)));
      const best = pages.bestDisclaimer;
      return {
        member: MemberId.parse(member),
        version: 1,
        character: profiles[index]?.character ?? null,
        checkedIn: page.checkedIn,
        plannedDays: page.plannedDays,
        trainedDays: page.trainedDays,
        days: page.days.map(({ day, kind, sport, minutes }) => ({
          day,
          kind,
          ...(sport === undefined ? {} : { sport }),
          ...(minutes === undefined ? {} : { minutes }),
        })),
        healthyMeals: page.healthyMeals,
        cheatMeals: page.cheatMeals,
        reactionsReceived: page.reactionsReceived,
        ...(page.reachedAt === undefined ? {} : { reachedAt: page.reachedAt }),
        ...(hottest === undefined ? {} : { hottest }),
        ...(best?.author === member
          ? {
              bestDisclaimer: { checkIn: best.checkIn, text: best.text, reactions: best.reactions },
            }
          : {}),
      };
    }),
  };
  // A week nobody in the squad checked in has no 战报 to keep (one before the squad began, say),
  // so nothing is stored: any member can ask for any past week.
  return story.members.some(({ checkedIn }) => checkedIn) ? deps.awards.freezeStory(story) : story;
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
  if (deps.clock() < (await awardsTimeFor(deps, { squad, weekStart }))) {
    throw new WeekStoryNotReadyError(weekStart);
  }
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
        checkIns: checkIns.map((record) => weekCheckIn(record, squadWeek)),
      };
    }),
  );
}
function weekCheckIn(
  record: CheckInRecord,
  { reactions, comments }: Pick<SquadWeekCheckIns, 'reactions' | 'comments'>,
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
    comments: (comments.get(record.id) ?? []).map(({ member, text, replyTo }) => ({
      member: MemberId.parse(member),
      text,
      ...(replyTo === undefined ? {} : { replyTo: MemberId.parse(replyTo) }),
    })),
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
      return {
        ...base,
        text: record.disclaimer.text,
        ...(record.disclaimer.restDay === true ? { restDay: true } : {}),
      };
  }
}

/**
 * The member's part with its hottest post's photos cut to those the post still has: an edit
 * that took a photo off also took it out of Storage. Its words stay as they were frozen.
 */
async function withPhotosStillPosted(
  deps: Pick<WeeklyAwardsDependencies, 'checkIns'>,
  member: StoryMember,
): Promise<StoryMember> {
  const { hottest } = member;
  if (hottest === undefined || hottest.photos.length === 0) return member;
  const post = await deps.checkIns.current(CheckInId.parse(hottest.checkIn));
  if (post === undefined) return member;
  const posted = new Set<string>(photosOf(post).map(({ path }) => path));
  const photos = hottest.photos.filter((path) => posted.has(path));
  return photos.length === hottest.photos.length
    ? member
    : { ...member, hottest: { ...hottest, photos } };
}
