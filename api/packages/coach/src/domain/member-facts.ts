// What the coach can look up about each member beyond this week: their counts since they joined,
// the sport they train most, the weekly titles they won, this week's plan (出赛表) and its
// 饮食小目标. The model sees each member as 队员N.

import { writeIn, type ReaderLanguage } from '@wildcard/language-model';

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
  /** This week's 饮食小目标 in words, in the order picked: eating habits, never a number. */
  readonly fuelGoals: readonly string[];
}

const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/** A plan day in words: `游泳`, `练` (any sport) or `休息`. */
function planDayWords(day: PlanDayFacts): string {
  return day.kind === 'rest' ? '休息' : (day.sport ?? '练');
}

/** This week's 饮食小目标 as a sentence. */
function fuelWords(goals: readonly string[]): string {
  return goals.length === 0 ? '这周没定饮食小目标' : `这周的饮食小目标：${goals.join('、')}`;
}

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
        .map((day, index) => `${WEEKDAYS[index] ?? ''}${planDayWords(day)}`)
        .join('，');
      return `${counts}${top}${titles}\n本周出赛表：${plan}。${fuelWords(each.fuelGoals)}。`;
    })
    .join('\n');
}

/** What the daily wake tells the coach about one member it writes a morning note to. */
export interface NoteBrief {
  /** The member as the model knows them: 队员N. */
  readonly name: string;
  /** The language their app speaks, which their note is written in. */
  readonly language?: ReaderLanguage;
  /** Days this week with a 练了 so far. */
  readonly trainedDays: number;
  /** Today's plan and this week's 饮食小目标, when they could be read. */
  readonly plan?: { readonly today: PlanDayFacts; readonly fuelGoals: readonly string[] };
}

/** The weekday of a `YYYY-MM-DD` day, Monday 0, as the plan counts it. */
export function planIndexOf(day: string): number {
  return (new Date(`${day}T00:00:00Z`).getUTCDay() + 6) % 7;
}

/** `周四`, for a `YYYY-MM-DD` day. */
export function weekdayOf(day: string): string {
  return WEEKDAYS[planIndexOf(day)] ?? '';
}

/** One member's line in the daily task, for their morning note. */
export function briefLine(brief: NoteBrief): string {
  const language = brief.language === undefined ? '' : ` ${writeIn(brief.language)}`;
  const trained = `这周已经练了 ${String(brief.trainedDays)} 天`;
  if (brief.plan === undefined) return `- ${brief.name}：${trained}。${language}`;
  const { today, fuelGoals } = brief.plan;
  const plan =
    today.kind === 'rest' ? '今天出赛表是休息日' : `今天出赛表排了${planDayWords(today)}`;
  return `- ${brief.name}：${plan}；${fuelWords(fuelGoals)}；${trained}。${language}`;
}
