import { z } from 'zod';

import type { CheckInId, CheckInRecord, MemberId } from './check-in.js';
import { trainedDays, type Week } from './days.js';
import { ReactionKind, type Reaction } from './reaction.js';

// The Sunday summary (周日战报): a squad's week as awards and counts. Every award and every
// count is one entry in a registry below, keyed by its kind, so adding one is adding a kind to
// its enum and its rule next to it; the compiler asks for both. Reaction counts come from
// `ReactionKind`, so a new reaction shows up here without a change. Awards only ever name
// winners: nobody is ranked last, and a member's own counts go only to them.

/** One member's week in a squad: their plan and what they sent to the squad. */
export interface MemberWeek {
  readonly member: MemberId;
  /** Training days in the member's plan for the week. */
  readonly plannedDays: number;
  /** Their check-ins on the week's days sent to this squad, oldest first. */
  readonly checkIns: readonly CheckInRecord[];
}

/** What a squad's week summary is made from. */
export interface WeekFacts {
  readonly week: Week;
  /** Everyone in the squad now, in the order they joined. */
  readonly members: readonly MemberWeek[];
  /** Reactions on the week's check-ins, from members of the squad now. */
  readonly reactions: ReadonlyMap<CheckInId, readonly Reaction[]>;
}

/** Someone an award went to, with the number they won it by, and the check-in if it was one. */
export interface Winner {
  readonly member: MemberId;
  readonly value: number;
  readonly checkIn?: CheckInId;
}

/**
 * The awards of a week. `planCompleted` (领奖台): everyone who trained at least as many days as
 * they planned, and at least one, by their trained days. `crown` (皇冠): those on the podium
 * with the most trained days, all of them on a tie. `bestDisclaimer` (本周最佳请假条): the
 * 请假条 with the most reactions, at least one, the earliest posted on a tie, by its reactions.
 */
export const AwardKind = z.enum(['planCompleted', 'crown', 'bestDisclaimer']);
export type AwardKind = z.infer<typeof AwardKind>;

/** The members' counts: each member's own, and the squad's as their sum. */
export const StatKind = z.enum([
  'trainedDays',
  'plannedDays',
  'checkIns',
  'disclaimers',
  'healthyMeals',
  'cheatMeals',
  'reactionsReceived',
]);
export type StatKind = z.infer<typeof StatKind>;

/** A week's award: its winners, none when nobody won it. */
type AwardRule = (facts: WeekFacts) => Winner[];
/** One member's count for the week. */
type StatRule = (member: MemberWeek, facts: WeekFacts) => number;

const trainedDaysOf = (member: MemberWeek, facts: WeekFacts) =>
  trainedDays(member.checkIns, facts.week.days);
const ofKind = (kind: CheckInRecord['kind']) => (member: MemberWeek) =>
  member.checkIns.filter((each) => each.kind === kind).length;
const reactionsOn = (facts: WeekFacts, checkIn: CheckInId) =>
  facts.reactions.get(checkIn)?.length ?? 0;

const podium: AwardRule = (facts) =>
  facts.members
    .map((member) => ({ member, value: trainedDaysOf(member, facts) }))
    .filter(({ member, value }) => value > 0 && value >= member.plannedDays)
    .map(({ member, value }) => ({ member: member.member, value }));

const AWARDS: Record<AwardKind, AwardRule> = {
  planCompleted: podium,
  crown: (facts) => {
    const onPodium = podium(facts);
    const most = Math.max(0, ...onPodium.map(({ value }) => value));
    return onPodium.filter(({ value }) => value === most);
  },
  bestDisclaimer: (facts) => {
    let best: Required<Winner> | undefined;
    let bestAt = 0;
    for (const each of facts.members.flatMap(({ checkIns }) => checkIns)) {
      if (each.kind !== 'disclaimer') continue;
      const value = reactionsOn(facts, each.id);
      const at = each.createdAt.getTime();
      const better =
        best === undefined
          ? value > 0
          : value > best.value || (value === best.value && at < bestAt);
      if (!better) continue;
      best = { member: each.member, value, checkIn: each.id };
      bestAt = at;
    }
    return best === undefined ? [] : [best];
  },
};

const STATS: Record<StatKind, StatRule> = {
  trainedDays: trainedDaysOf,
  plannedDays: (member) => member.plannedDays,
  checkIns: (member) => member.checkIns.length,
  disclaimers: ofKind('disclaimer'),
  healthyMeals: ofKind('healthyMeal'),
  cheatMeals: ofKind('cheatMeal'),
  reactionsReceived: (member, facts) =>
    member.checkIns.reduce((sum, each) => sum + reactionsOn(facts, each.id), 0),
};

export interface Award {
  readonly kind: AwardKind;
  readonly winners: Winner[];
}
export interface Stat {
  readonly kind: StatKind;
  readonly value: number;
}

/** A week's summary for one member of the squad. */
export interface WeekSummary {
  /** Every award someone won, in `AwardKind`'s order. */
  readonly awards: Award[];
  readonly squad: {
    readonly stats: Stat[];
    readonly reactions: { readonly kind: ReactionKind; readonly count: number }[];
  };
  readonly me: {
    readonly stats: Stat[];
    /** Reactions the member got on the week's check-ins, and left on teammates' ones. */
    readonly reactions: {
      readonly kind: ReactionKind;
      readonly received: number;
      readonly given: number;
    }[];
  };
}

/** The summary of a squad's week, as `viewer` (one of its members) sees it. */
export function summarizeWeek(facts: WeekFacts, viewer: MemberId): WeekSummary {
  const me = facts.members.find(({ member }) => member === viewer);
  const statsOf = (members: readonly MemberWeek[]) =>
    StatKind.options.map((kind) => ({
      kind,
      value: members.reduce((sum, member) => sum + STATS[kind](member, facts), 0),
    }));
  const mine = new Set(me?.checkIns.map(({ id }) => id));
  const all = [...facts.reactions.entries()].flatMap(([checkIn, reactions]) =>
    reactions.map((reaction) => ({ checkIn, reaction })),
  );
  const count = (kind: ReactionKind, keep: (each: (typeof all)[number]) => boolean) =>
    all.filter((each) => each.reaction.kind === kind && keep(each)).length;

  return {
    awards: AwardKind.options
      .map((kind) => ({ kind, winners: AWARDS[kind](facts) }))
      .filter(({ winners }) => winners.length > 0),
    squad: {
      stats: statsOf(facts.members),
      reactions: ReactionKind.options.map((kind) => ({ kind, count: count(kind, () => true) })),
    },
    me: {
      stats: statsOf(me === undefined ? [] : [me]),
      reactions: ReactionKind.options.map((kind) => ({
        kind,
        received: count(kind, ({ checkIn }) => mine.has(checkIn)),
        given: count(kind, ({ reaction }) => reaction.member === viewer),
      })),
    },
  };
}
