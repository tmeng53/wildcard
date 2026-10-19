import type { AwardKind, ReactionKind, StatKind } from '@wildcard/check-ins';

// The words of the Sunday summary (周日战报). The app shows what the API sends, so a new award,
// count or reaction reaches every installed app with no release: add its kind and its copy here,
// and the compiler asks for both languages.

/** The languages the summary is written in; Chinese first. */
export type Language = 'zh-Hans' | 'en';

/** The first language in `Accept-Language` the summary is written in; Chinese when none is. */
export function languageOf(acceptLanguage: string | undefined): Language {
  for (const range of (acceptLanguage ?? '').split(',')) {
    const tag = range.split(';')[0]?.trim().toLowerCase() ?? '';
    if (tag.startsWith('zh')) return 'zh-Hans';
    if (tag.startsWith('en')) return 'en';
  }
  return 'zh-Hans';
}

type Words = Readonly<Record<Language, string>>;

interface AwardCopy {
  /** An SF Symbol name the app shows next to the award. */
  readonly symbol: string;
  readonly title: Words;
  /** What a winner won it by, from the award's value. */
  readonly winner: (value: number) => Words;
}

const days = (value: number): Words => ({
  'zh-Hans': `练了 ${String(value)} 天`,
  en: `Trained ${String(value)} ${value === 1 ? 'day' : 'days'}`,
});

export const AWARD_COPY: Readonly<Record<AwardKind, AwardCopy>> = {
  planCompleted: {
    symbol: 'checkmark.seal.fill',
    title: { 'zh-Hans': '领奖台', en: 'Podium' },
    winner: days,
  },
  crown: {
    symbol: 'crown.fill',
    title: { 'zh-Hans': '皇冠', en: 'Crown' },
    winner: days,
  },
  bestDisclaimer: {
    symbol: 'text.bubble.fill',
    title: { 'zh-Hans': '本周最佳请假条', en: 'Day-off note of the week' },
    winner: (value) => ({
      'zh-Hans': `${String(value)} 个回应`,
      en: `${String(value)} ${value === 1 ? 'reaction' : 'reactions'}`,
    }),
  },
};

export const STAT_COPY: Readonly<Record<StatKind, Words>> = {
  trainedDays: { 'zh-Hans': '训练天数', en: 'Days trained' },
  plannedDays: { 'zh-Hans': '计划天数', en: 'Days planned' },
  checkIns: { 'zh-Hans': '打卡', en: 'Check-ins' },
  disclaimers: { 'zh-Hans': '请假条', en: 'Day-off notes' },
  healthyMeals: { 'zh-Hans': '健康餐', en: 'Clean meals' },
  cheatMeals: { 'zh-Hans': '放纵餐', en: 'Cheat meals' },
  reactionsReceived: { 'zh-Hans': '收到的回应', en: 'Reactions received' },
};

export const REACTION_COPY: Readonly<Record<ReactionKind, Words>> = {
  cheer: { 'zh-Hans': '加油', en: 'Cheer' },
  highlight: { 'zh-Hans': '名场面', en: 'Highlights' },
  lol: { 'zh-Hans': '笑死', en: 'LOL' },
};
