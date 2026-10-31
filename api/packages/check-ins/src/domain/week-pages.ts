import type { CheckInId, CheckInRecord, LocalDay, MemberId } from './check-in.js';
import {
  statsOf,
  weekAwards,
  type AwardKind,
  type Stat,
  type StatKind,
  type WeekFacts,
} from './week-summary.js';
import type { PlanDay } from './weekly-plan.js';

// The Sunday 战报's pages without AI: who stands on the podium, each member's days, the
// squad's meals, the best 请假条 and the squad's days against its plans. The same rules as the
// week summary's awards and counts, read from the week as the awards saw it. A page with
// nothing to show is left out, so a quiet week isn't told how short it fell.

/** What a day of a member's week was: a 练了 wins over a 请假条, which wins over a rest day. */
export interface StoryDay {
  readonly day: LocalDay;
  readonly kind: 'trained' | 'rest' | 'disclaimer' | 'none';
  /** For a trained day: its first 练了's listed sport; missing for a sport of the member's own. */
  readonly sport?: string;
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
}

export interface WeekPages {
  /** 领奖台: the crown winner in the middle, up to 2 others who finished their plan beside. */
  readonly podium?: { readonly champion: MemberId; readonly sides: readonly MemberId[] };
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

/** The most podium sides the page has room for. */
const SIDES_MAX = 2;

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
    return {
      member,
      plannedDays: stat('plannedDays'),
      trainedDays: stat('trainedDays'),
      days: facts.week.days.map((day, index) => dayOf(checkIns, { day, planned: plan[index] })),
      healthyMeals: stat('healthyMeals'),
      cheatMeals: stat('cheatMeals'),
      reactionsReceived: stat('reactionsReceived'),
      checkedIn: checkIns.length > 0,
    };
  });

  const crown = winners('crown').map(({ member }) => member);
  const champion = crown[0] ?? winners('planCompleted')[0]?.member;
  const sides = [
    ...new Set([...crown.slice(1), ...winners('planCompleted').map(({ member }) => member)]),
  ]
    .filter((member) => member !== champion)
    .slice(0, SIDES_MAX);

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
    ...(champion === undefined ? {} : { podium: { champion, sides } }),
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

/** A member's day: their first 练了's sport, else a 请假条, else a planned rest day. */
function dayOf(
  checkIns: readonly CheckInRecord[],
  { day, planned }: { readonly day: LocalDay; readonly planned: PlanDay | undefined },
): StoryDay {
  const posts = checkIns.filter((each) => each.day === day);
  const trained = posts.find((each) => each.kind === 'trained');
  if (trained?.kind === 'trained') {
    // A sport of the member's own is their words, which the frozen 战报 keeps only with the post.
    const { sport } = trained.training;
    return sport === 'custom' ? { day, kind: 'trained' } : { day, kind: 'trained', sport };
  }
  if (posts.some(({ kind }) => kind === 'disclaimer')) return { day, kind: 'disclaimer' };
  if (planned?.kind === 'rest') return { day, kind: 'rest' };
  return { day, kind: 'none' };
}
