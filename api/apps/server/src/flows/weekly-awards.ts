import {
  SquadId as CheckInSquad,
  WeekStart as CheckInWeek,
  photosOf,
  type CheckInRecord,
  type CheckIns,
  type SquadWeekCheckIns,
} from '@wildcard/check-ins';
import type { Members } from '@wildcard/members';
import { MemberId as PushMember, type Push, type PushNotification } from '@wildcard/push';
import { MemberId as SquadsMember, SquadId as SquadsSquad, type Squads } from '@wildcard/squads';
import {
  MemberId,
  awardsTimeOf,
  latestAwardedWeek,
  type MemberAwards,
  type MemberWeek,
  type SquadId,
  type WeekCheckIn,
  type WeekStart,
  type WeeklyAwards,
  WeekStoryNotReadyError,
} from '@wildcard/weekly-awards';

import type { Log } from '../log.js';

// The weekly awards across modules: the week's check-ins from check-ins, members' clocks from
// members, the awards from weekly-awards, and the winners' push from push.

export interface WeeklyAwardsDependencies {
  readonly checkIns: CheckIns;
  readonly members: Members;
  readonly squads: Squads;
  readonly awards: WeeklyAwards;
  readonly push: Push;
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
          if ((await deps.awards.find({ squad, weekStart: week })) === undefined) {
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
  /** `pending`: due, but not written yet (the run hasn't reached the squad, or the model failed). */
  readonly status: 'ready' | 'pending';
  /** Members still in the squad, in the order they joined; empty until ready, or when nobody checked in. */
  readonly members: readonly MemberAwards[];
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
  const found = await deps.squads.find({
    squad: SquadsSquad.parse(squad),
    viewer: SquadsMember.parse(viewer),
  });
  const awardsAt = awardsTimeOf(weekStart);
  if (deps.clock() < awardsAt) throw new WeekStoryNotReadyError(weekStart);
  const header = { squad: { id: squad, name: found.name } };
  const awards = await deps.awards.find({ squad, weekStart });
  if (awards !== undefined) {
    // Members who left take their awards with them, as their check-ins leave the feed.
    const inSquad = new Set<string>(found.members.map(({ member }) => member));
    const members = awards.members.filter(({ member }) => inSquad.has(member));
    return { ...header, status: 'ready', members };
  }
  const week = await deps.checkIns.squadWeekCheckIns({
    squad: CheckInSquad.parse(squad),
    weekStart: CheckInWeek.parse(weekStart),
    before: awardsAt,
  });
  const anyone = week.members.some(({ checkIns }) => checkIns.length > 0);
  return { ...header, status: anyone ? 'pending' : 'ready', members: [] };
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
