import {
  isLeave,
  type CheckInId,
  type CheckInRecord,
  type LocalDay,
  type MemberId,
} from './check-in.js';
import { byTrainedThenReached, trainedDaysReachedAt } from './days.js';
import {
  statsOf,
  weekAwards,
  type AwardKind,
  type Stat,
  type StatKind,
  type WeekFacts,
} from './week-summary.js';
import type { PlanDay } from './weekly-plan.js';

// The Sunday 战报's pages without AI: each member's days (the podium is read from them), the
// squad's meals, the best 请假条 and the squad's days against its plans. The same rules as the
// week summary's awards and counts, read from the week as the awards saw it. A page with
// nothing to show is left out, so a quiet week isn't told how short it fell.

/** What a day of a member's week was: a 练了 wins over a 请假条, which wins over a rest day. */
export interface StoryDay {
  readonly day: LocalDay;
  readonly kind: 'trained' | 'rest' | 'disclaimer' | 'none';
  /** For a trained day: its first 练了's listed sport; missing for a sport of the member's own. */
  readonly sport?: string;
  /** For a trained day: the minutes its 练了 logged, when any did (minutes are never asked for). */
  readonly minutes?: number;
}

/** One member's week, for 你的一周. */
export interface MemberPage {
  readonly member: MemberId;
  /** Training days in their plan. */
  readonly plannedDays: number;
  readonly trainedDays: number;
  /** Monday first. */
  readonly days: readonly StoryDay[];
  readonly healthyMeals: number;
  readonly cheatMeals: number;
  readonly reactionsReceived: number;
  /** Whether they checked in anything that week. */
  readonly checkedIn: boolean;
  /** When they reached their days trained (ISO time), if they trained: it breaks ties on the podium. */
  readonly reachedAt?: string;
}

export interface WeekPages {
  /** Every member, in the order they joined. */
  readonly members: readonly MemberPage[];
  /** 吃了: the squad's meals, each member eating what they logged more of (健康餐 on a tie). */
  readonly meals?: {
    readonly healthy: number;
    readonly cheat: number;
    readonly eaters: readonly { readonly member: MemberId; readonly more: 'healthy' | 'cheat' }[];
  };
  /** 最佳请假条: the one with the most reactions, as the week summary's award. */
  readonly bestDisclaimer?: {
    readonly checkIn: CheckInId;
    readonly author: MemberId;
    readonly text: string;
    readonly reactions: number;
  };
  /** 这一周: the squad's days trained against its plans; only when someone trained. */
  readonly ending?: { readonly done: number; readonly plan: number };
}

/** The most members the podium has room for: the champion and two sides. */
const PODIUM_MAX = 3;

/** 领奖台: who stands on it, and which of them trained every day they planned. */
export interface Podium<Member> {
  /** The most days trained, in the middle with the crown; on a tie whoever reached them first. */
  readonly champion: Member;
  /** Up to 2 next by days trained (ties as for the champion), left then right. */
  readonly sides: readonly Member[];
  /** Those on it who trained at least as many days as they planned (练够计划). */
  readonly planDone: readonly Member[];
  /** Whether reaching the tied days first decided a place on it or the last place just off it. */
  readonly tieBrokenByTime: boolean;
}

/**
 * The podium of a week: the top 3 by days trained, at least one, every week, whether or not
 * they finished their plan, a tie going to whoever reached those days first. The champion holds
 * the week's crown (`weekAwards`), so they pick next week's scene. `undefined` when nobody
 * trained. Members come in the order they joined.
 */
export function podiumOf<Member>(
  members: readonly {
    readonly member: Member;
    readonly trainedDays: number;
    readonly plannedDays: number;
    /** When they reached their days trained (an ISO time), if they trained. */
    readonly reachedAt?: string | undefined;
  }[],
): Podium<Member> | undefined {
  const ranked = members
    .filter(({ trainedDays }) => trainedDays > 0)
    .toSorted(byTrainedThenReached);
  const top = ranked.slice(0, PODIUM_MAX);
  const [champion, ...sides] = top;
  if (champion === undefined) return undefined;
  // The time decided a place when, without it, join order would put someone else on the podium
  // or in another place on it.
  const byDays = members
    .filter(({ trainedDays }) => trainedDays > 0)
    .toSorted((a, b) => b.trainedDays - a.trainedDays);
  const tieBrokenByTime = top.some((each, index) => each !== byDays[index]);
  return {
    tieBrokenByTime,
    champion: champion.member,
    sides: sides.map(({ member }) => member),
    planDone: top
      .filter(({ trainedDays, plannedDays }) => trainedDays >= plannedDays)
      .map(({ member }) => member),
  };
}

/** The story's pages for a squad's week, from its facts and each member's plan (Monday first). */
export function weekPagesOf(
  facts: WeekFacts,
  plans: ReadonlyMap<MemberId, readonly PlanDay[]>,
): WeekPages {
  const awards = weekAwards(facts);
  const winners = (kind: AwardKind) => awards.find((award) => award.kind === kind)?.winners ?? [];
  const count = (stats: readonly Stat[], kind: StatKind) =>
    stats.find((stat) => stat.kind === kind)?.value ?? 0;
  const squad = statsOf(facts, facts.members);

  const members = facts.members.map((each): MemberPage => {
    const { member, checkIns } = each;
    const stats = statsOf(facts, [each]);
    const stat = (kind: StatKind) => count(stats, kind);
    const plan = plans.get(member) ?? [];
    const reached = trainedDaysReachedAt(checkIns, {
      days: facts.week.days,
      count: stat('trainedDays'),
    });
    return {
      member,
      plannedDays: stat('plannedDays'),
      trainedDays: stat('trainedDays'),
      days: facts.week.days.map((day, index) => dayOf(checkIns, { day, planned: plan[index] })),
      healthyMeals: stat('healthyMeals'),
      cheatMeals: stat('cheatMeals'),
      reactionsReceived: stat('reactionsReceived'),
      checkedIn: checkIns.length > 0,
      ...(reached === undefined ? {} : { reachedAt: reached.toISOString() }),
    };
  });

  const eaters = members
    .filter(({ healthyMeals, cheatMeals }) => healthyMeals + cheatMeals > 0)
    .map(({ member, healthyMeals, cheatMeals }) => ({
      member,
      more: cheatMeals > healthyMeals ? ('cheat' as const) : ('healthy' as const),
    }));

  const best = winners('bestDisclaimer')[0];
  const note = facts.members
    .flatMap(({ checkIns }) => checkIns)
    .find(({ id }) => id === best?.checkIn);

  const done = count(squad, 'trainedDays');
  return {
    members,
    ...(eaters.length === 0
      ? {}
      : {
          meals: {
            healthy: count(squad, 'healthyMeals'),
            cheat: count(squad, 'cheatMeals'),
            eaters,
          },
        }),
    ...(best === undefined || note?.kind !== 'disclaimer'
      ? {}
      : {
          bestDisclaimer: {
            checkIn: note.id,
            author: note.member,
            text: note.disclaimer.text,
            reactions: best.value,
          },
        }),
    ...(done === 0 ? {} : { ending: { done, plan: count(squad, 'plannedDays') } }),
  };
}

/** A member's day: their first 练了's sport, else a 请假条, else a rest (planned, or a 休息). */
function dayOf(
  checkIns: readonly CheckInRecord[],
  { day, planned }: { readonly day: LocalDay; readonly planned: PlanDay | undefined },
): StoryDay {
  const posts = checkIns.filter((each) => each.day === day);
  const trained = posts.find((each) => each.kind === 'trained');
  if (trained?.kind === 'trained') {
    // A sport of the member's own is their words, which the frozen 战报 keeps only with the post.
    const { sport } = trained.training;
    const minutes = posts.reduce(
      (sum, each) => sum + (each.kind === 'trained' ? (each.training.minutes ?? 0) : 0),
      0,
    );
    return {
      day,
      kind: 'trained',
      ...(sport === 'custom' ? {} : { sport }),
      ...(minutes === 0 ? {} : { minutes }),
    };
  }
  if (posts.some(isLeave)) return { day, kind: 'disclaimer' };
  if (planned?.kind === 'rest' || posts.some(({ kind }) => kind === 'disclaimer')) {
    return { day, kind: 'rest' };
  }
  return { day, kind: 'none' };
}
