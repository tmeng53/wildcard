// What the coach can look up about each member beyond this week: their counts since they joined,
// the sport they train most, the weekly titles they won and this week's plan (出赛表). The model
// sees each member as 队员N.

/** One day of a member's plan: a sport by its name (or any sport), or rest. */
export type PlanDayFacts =
  { readonly kind: 'train'; readonly sport?: string } | { readonly kind: 'rest' };

export interface MemberFacts {
  readonly member: string;
  /** Days with a 练了, ever. */
  readonly trainedDays: number;
  readonly healthyMeals: number;
  readonly cheatMeals: number;
  readonly disclaimers: number;
  /** The sport they logged the most 练了 for, by its name, with how many. */
  readonly topSport?: { readonly name: string; readonly checkIns: number };
  /** Weekly titles won, and the latest. */
  readonly titles: number;
  readonly latestTitle?: string;
  /** This week's plan, Monday first. */
  readonly plan: readonly PlanDayFacts[];
}

const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/** The `member_stats` tool's answer: a few lines a member. */
export function factsText(
  facts: readonly MemberFacts[],
  roster: ReadonlyMap<string, string>,
): string {
  if (facts.length === 0) return '还没有队员的数据。';
  return facts
    .map((each) => {
      const who = roster.get(each.member) ?? '队员';
      const counts = `${who}：一共练了 ${String(each.trainedDays)} 天，健康餐 ${String(each.healthyMeals)} 次，坦白放纵餐 ${String(each.cheatMeals)} 次，请假条 ${String(each.disclaimers)} 次。`;
      const top =
        each.topSport === undefined
          ? ''
          : `最常练${each.topSport.name}（${String(each.topSport.checkIns)} 次）。`;
      const titles =
        each.titles === 0
          ? '还没拿过周奖。'
          : `拿过 ${String(each.titles)} 个周奖${each.latestTitle === undefined ? '' : `，最近一个是「${each.latestTitle}」`}。`;
      const plan = each.plan
        .map((day, index) => {
          const name = WEEKDAYS[index] ?? '';
          if (day.kind === 'rest') return `${name}休息`;
          return `${name}${day.sport ?? '练'}`;
        })
        .join('，');
      return `${counts}${top}${titles}\n本周出赛表：${plan}。`;
    })
    .join('\n');
}
