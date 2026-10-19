import type { AwardKind, ReactionKind, StatKind } from '@wildcard/check-ins';

// The words of the Sunday summary (周日战报). The app shows what the API sends, so a new award or
// count reaches every installed app with no release: add its kind and its copy here, and the
// compiler asks for both languages. A new reaction kind shows up here the same way, but the
// reaction routes still send a closed enum, so adding one is still an app release.

/** The languages the summary is written in; Chinese first. */
export type Language = 'zh-Hans' | 'en';

const isLanguage = (tag: string, language: string) =>
  tag === language || tag.startsWith(`${language}-`);

/**
 * The language in `Accept-Language` the summary is written in that the client weighs highest
 * (`q`, 1 when left out), the earlier one on a tie; Chinese when none is. A range weighed `q=0`
 * is not acceptable.
 */
export function languageOf(acceptLanguage: string | undefined): Language {
  let best: { language: Language; q: number } | undefined;
  for (const range of (acceptLanguage ?? '').split(',')) {
    const [tag = '', ...parameters] = range.split(';').map((part) => part.trim().toLowerCase());
    const weight = parameters.find((parameter) => parameter.startsWith('q='));
    const q = weight === undefined ? 1 : Number(weight.slice(2));
    if (!(q > 0 && q <= 1)) continue;
    const language = isLanguage(tag, 'zh') ? 'zh-Hans' : isLanguage(tag, 'en') ? 'en' : undefined;
    if (language !== undefined && (best === undefined || q > best.q)) best = { language, q };
  }
  return best?.language ?? 'zh-Hans';
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
