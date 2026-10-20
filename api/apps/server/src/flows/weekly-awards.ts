import {
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
import { MemberId as SquadsMember, SquadId as SquadsSquad, type Squads } from '@wildcard/squads';
import {
  MemberId,
  awardsTimeOf,
  latestAwardedWeek,
  topCheckInOf,
  type Failures,
  type MemberAwards,
  type MemberWeek,
  type SquadId,
  type TopCheckIn,
  type WeekCheckIn,
  type WeekStart,
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
  /** The week whose awards it gave. */
  readonly week: WeekStart;
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
 * written is tried again on the next run, and a squad already done is only checked. Check-ins
 * made after the awards' moment still count for the week, only not for its awards.
 */
export async function giveWeeklyAwards(deps: WeeklyAwardsDependencies): Promise<WeeklyAwardsRun> {
  const week = latestAwardedWeek(deps.clock());
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
            const members = await memberWeeks(deps, { squad, week, before });
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
  return { week, squads: squads.length, given, failed, told };
}

/** A squad's week story as one of its members reads it: the awards, once they are due. */
export interface SquadStory {
  readonly squad: { readonly id: SquadId; readonly name: string };
  /**
   * `pending`: due, but the titles aren't written yet (the run hasn't reached the squad, or the
   * model failed). Only the titles wait: the pages without AI are there either way.
   */
  readonly status: 'ready' | 'pending';
  /** Members still in the squad, in the order they joined; empty until ready, or when nobody checked in. */
  readonly members: readonly MemberAwards[];
  /** The viewer's check-in with the most reactions before the awards, when one had any. */
  readonly hottest?: TopCheckIn;
}

/**
 * A squad's week story for one of its members. Throws `WeekStoryNotReadyError` before the
 * week's awards (Sunday 8pm Eastern), `SquadNotJoinedError` for anyone not in the squad.
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
  const header = { squad: { id: squad, name: found.name } };
  const state = await deps.awards.find({ squad, weekStart });
  if (state?.status === 'given') {
    // Members who left take their awards with them, as their check-ins leave the feed.
    const inSquad = new Set<string>(found.members.map(({ member }) => member));
    const members = state.awards.members.filter(({ member }) => inSquad.has(member));
    const hottest = members.find(({ member }) => member === MemberId.parse(viewer))?.topCheckIn;
    return { ...header, status: 'ready', members, ...(hottest === undefined ? {} : { hottest }) };
  }
  // Not written yet: the hottest check-in as the awards will see it, from the week so far.
  const week = await deps.checkIns.squadWeekCheckIns({
    squad: CheckInSquad.parse(squad),
    weekStart: CheckInWeek.parse(weekStart),
    before: awardsTimeOf(weekStart),
  });
  const anyone = week.members.some(({ checkIns }) => checkIns.length > 0);
  const mine = week.members.find(({ member }) => member === viewer)?.checkIns ?? [];
  const hottest = topCheckInOf(mine.map((record) => weekCheckIn(record, week.reactions)));
  return {
    ...header,
    status: anyone ? 'pending' : 'ready',
    members: [],
    ...(hottest === undefined ? {} : { hottest }),
  };
}

/**
 * A member nudging the organisers (催一下主办方) about a story whose titles haven't come: the
 * first nudge for a squad's week tells every admin, with the failed tries and why; later ones,
 * and nudges once the titles are written, do nothing. Throws as `squadStory` does.
 */
export async function nudgeOrganisers(
  deps: Pick<WeeklyAwardsDependencies, 'squads' | 'awards' | 'push' | 'admins' | 'clock' | 'log'>,
  {
    viewer,
    squad,
    weekStart,
  }: { readonly viewer: string; readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<void> {
  const found = await dueSquad(deps, { viewer, squad, weekStart });
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

/** Everyone in the squad with their check-ins before the awards, as the awards read them. */
async function memberWeeks(
  deps: Pick<WeeklyAwardsDependencies, 'checkIns' | 'members'>,
  {
    squad,
    week,
    before,
  }: { readonly squad: SquadId; readonly week: WeekStart; readonly before: Date },
): Promise<MemberWeek[]> {
  const squadWeek = await deps.checkIns.squadWeekCheckIns({
    squad: CheckInSquad.parse(squad),
    weekStart: CheckInWeek.parse(week),
    before,
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
  for (const { kind } of reactions.get(record.id) ?? []) counts[kind] = (counts[kind] ?? 0) + 1;
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
