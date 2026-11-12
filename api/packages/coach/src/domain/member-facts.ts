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

/** One of a member's posts this week, as their morning note's brief reads it. */
export interface WeekPost {
  /** The member's own day it counts for, `YYYY-MM-DD`. */
  readonly day: string;
  /** What it was: `游泳 45 分钟`, `健康餐`, `计划休息`. */
  readonly what: string;
}

/** What the daily wake tells the coach about one member it writes a morning note to. */
export interface NoteBrief {
  /** The member as the model knows them: 队员N. */
  readonly name: string;
  /** The nickname squadmates know them by, if they gave one. */
  readonly nickname?: string;
  /** What they did before, ever: for a member who just joined, whom the coach knows nothing of. */
  readonly record?: {
    readonly trainedDays: number;
    readonly topSport?: { readonly name: string; readonly checkIns: number };
  };
  /** The language their app speaks, which their note is written in. */
  readonly language?: ReaderLanguage;
  /** Days this week with a 练了 so far. */
  readonly trainedDays: number;
  /** What they posted to the squad this week so far, oldest first. */
  readonly posts?: readonly WeekPost[];
  /** This week's whole plan, Monday first, and its 饮食小目标, when they could be read. */
  readonly plan?: { readonly week: readonly PlanDayFacts[]; readonly fuelGoals: readonly string[] };
  /** Today's (and yesterday's) weather where they are, in words starting 今天, when known. */
  readonly weather?: string;
}

/** The weekday of a `YYYY-MM-DD` day, Monday 0, as the plan counts it. */
export function planIndexOf(day: string): number {
  return (new Date(`${day}T00:00:00Z`).getUTCDay() + 6) % 7;
}

/** `周四`, for a `YYYY-MM-DD` day. */
export function weekdayOf(day: string): string {
  return WEEKDAYS[planIndexOf(day)] ?? '';
}

/** What a member posted this week, day by day: `周一游泳 45 分钟、健康餐，周三请假条`. */
function postsWords(posts: readonly WeekPost[]): string {
  if (posts.length === 0) return '还没发过';
  const days = new Map<string, string[]>();
  for (const { day, what } of posts) days.set(day, [...(days.get(day) ?? []), what]);
  return [...days.entries()]
    .toSorted(([a], [b]) => a.localeCompare(b))
    .map(([day, theirs]) => `${weekdayOf(day)}${theirs.join('、')}`)
    .join('，');
}

/**
 * One member's block in a task, for the note written to them: their week, plan and posts, one
 * fact a line under their name.
 */
export function briefBlock(brief: NoteBrief): string {
  const lines = [`### ${brief.name}${brief.nickname === undefined ? '' : `（${brief.nickname}）`}`];
  if (brief.record !== undefined) {
    const top = brief.record.topSport;
    lines.push(
      `- 以前一共练了：${String(brief.record.trainedDays)} 天${top === undefined ? '' : `，练得最多的是${top.name}（${String(top.checkIns)} 次）`}`,
    );
  }
  if (brief.plan !== undefined) {
    const plan = brief.plan.week
      .map((day, index) => `${WEEKDAYS[index] ?? ''}${planDayWords(day)}`)
      .join('，');
    lines.push(`- 本周出赛表：${plan}`);
    lines.push(
      `- 饮食小目标：${brief.plan.fuelGoals.length === 0 ? '这周没定' : brief.plan.fuelGoals.join('、')}`,
    );
  }
  lines.push(`- 这周练了：${String(brief.trainedDays)} 天`);
  if (brief.posts !== undefined) lines.push(`- 这周发过：${postsWords(brief.posts)}`);
  if (brief.weather !== undefined) lines.push(`- 当地天气：${brief.weather}`);
  if (brief.language !== undefined) lines.push(`- ${writeIn(brief.language)}`);
  return lines.join('\n');
}
