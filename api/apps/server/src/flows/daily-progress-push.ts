import { MemberId as CheckInMember, SquadId, type CheckIns } from '@wildcard/check-ins';
import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import { MemberId as NudgeMember, type Nudges } from '@wildcard/nudges';
import {
  LocalDay,
  MemberId as PushMember,
  type DailyCandidate,
  type Push,
  type PushNotification,
} from '@wildcard/push';
import { MemberId as SquadMember, type Squads } from '@wildcard/squads';

import type { Log } from '../log.js';

/** The daily push goes out at this hour on each member's own clock, or later that evening. */
export const DAILY_PUSH_HOUR = 18;

/** How many members' pushes are put together at once. */
const AT_ONCE = 4;

/**
 * Teammates who did something for a member, by kind (`reaction`, a nudge's `poke`): each
 * person once per kind. The kind is the name the app's String Catalog keys the copy by.
 */
export type Interactions = ReadonlyMap<string, ReadonlySet<string>>;

/**
 * Where one sort of interaction comes from: reactions and nudges now, others as they land. A new
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

/** The interactions source built on nudges: pokes (`poke`). */
export function nudgeInteractions(nudges: Nudges): InteractionSource {
  return async ({ member, since, until }) =>
    nudges.received({ member: NudgeMember.parse(member), since, until });
}

/**
 * The kinds whose sender the push names (a poke names the poker), most telling first. The first
 * kind someone sent is the one named.
 */
const NAMED_KINDS = ['poke'] as const;

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
  /** Members whose push was due: past 6pm, a phone, not turned off, not handled today. */
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
 * Sends each member their one push of the day once their clock passes 6pm: the squad's week so
 * far and who reacted to, poked or otherwise cheered them on since their last one. Meant to run
 * every few minutes; each member's day is handled once, claimed before sending, so runs can overlap or
 * repeat. A member whose squad was quiet and who got nothing gets no push that day.
 */
export async function sendDailyProgress(
  deps: DailyProgressDependencies,
): Promise<DailyProgressRun> {
  const now = deps.clock();
  const evening = await deps.members.pastLocalHour({ hour: DAILY_PUSH_HOUR, now });
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
 * A member whose push is due, and what it covers: from their last one (or 6pm on their clock the
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
    named: await namedSender(deps.members, byKind),
  });
}

/** Who the push names: the first sender of the most telling kind who has a nickname. */
async function namedSender(
  members: Members,
  received: Interactions,
): Promise<{ readonly kind: string; readonly nickname: string } | undefined> {
  for (const kind of NAMED_KINDS) {
    const senders = [...(received.get(kind) ?? [])].map((each) => ProfileMember.parse(each));
    if (senders.length === 0) continue;
    const profiles = await members.squadmates(senders);
    for (const sender of senders) {
      const nickname = profiles.get(sender)?.character?.nickname;
      if (nickname !== undefined) return { kind, nickname };
    }
  }
  return undefined;
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
 * and how many teammates did something for the member. When someone nudged them, it names that
 * person instead (「小美拍了拍你」), with how many others sent the same kind (「小美和另外 2 人拍了拍
 * 你」); the key says which kind. `event` carries the people per kind, for the app to say more.
 */
export function dailyProgressNotification({
  day,
  squad,
  squadWeek,
  received,
  named,
}: {
  readonly day: string;
  readonly squad: string;
  readonly squadWeek: { readonly trainedDays: number; readonly plannedDays: number };
  readonly received: Interactions;
  /** The nudge's sender to name, and its kind. */
  readonly named?: { readonly kind: string; readonly nickname: string } | undefined;
}): PushNotification {
  const people = new Set([...received.values()].flatMap((each) => [...each])).size;
  const week = [String(squadWeek.trainedDays), String(squadWeek.plannedDays)];
  const others = named === undefined ? 0 : (received.get(named.kind)?.size ?? 1) - 1;
  const alert =
    named !== undefined
      ? others > 0
        ? {
            key: `push.dailyProgress.${named.kind}.more`,
            args: [...week, named.nickname, String(others)],
          }
        : { key: `push.dailyProgress.${named.kind}`, args: [...week, named.nickname] }
      : people === 0
        ? { key: 'push.dailyProgress', args: week }
        : { key: 'push.dailyProgress.received', args: [...week, String(people)] };
  return {
    alert,
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
