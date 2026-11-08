import { describe, expect, it } from 'vitest';

import {
  WeekSummaryWords,
  WeekSummaryWordsChange,
  inLanguage,
  winnerText,
} from './week-summary-words.js';

const counted = (one: string, other: string) => ({ one, other });
const award = {
  symbol: 'crown.fill',
  title: { 'zh-Hans': '皇冠', en: 'Crown', 'zh-Hant': '皇冠' },
  winner: {
    'zh-Hans': counted('练了 {n} 天', '练了 {n} 天'),
    en: counted('Trained {n} day', 'Trained {n} days'),
    'zh-Hant': counted('練了 {n} 天', '練了 {n} 天'),
  },
};
const stat = { 'zh-Hans': '打卡', en: 'Check-ins', 'zh-Hant': '打卡' };
const words = {
  version: 1,
  awards: { planCompleted: award, crown: award, bestDisclaimer: award },
  stats: {
    trainedDays: stat,
    plannedDays: stat,
    checkIns: stat,
    disclaimers: stat,
    healthyMeals: stat,
    cheatMeals: stat,
    reactionsReceived: stat,
  },
};

/** Words saved before Traditional Chinese came. */
const older = { 'zh-Hans': '打卡', en: 'Check-ins' };

describe('the week summary’s words', () => {
  it('count a winner’s value, one or other', () => {
    const parsed = WeekSummaryWords.parse(words);
    expect(winnerText(parsed, { kind: 'crown', value: 1, language: 'en' })).toBe('Trained 1 day');
    expect(winnerText(parsed, { kind: 'crown', value: 5, language: 'en' })).toBe('Trained 5 days');
    expect(winnerText(parsed, { kind: 'crown', value: 0, language: 'zh-Hans' })).toBe('练了 0 天');
    expect(winnerText(parsed, { kind: 'crown', value: 2, language: 'zh-Hant' })).toBe('練了 2 天');
  });

  it('read as Simplified Chinese where a phrase has no Traditional Chinese yet', () => {
    const title = { 'zh-Hans': '皇冠', en: 'Crown' };
    const winner = { 'zh-Hans': award.winner['zh-Hans'], en: award.winner.en };
    const parsed = WeekSummaryWords.parse({
      ...words,
      awards: { ...words.awards, crown: { ...award, title, winner } },
      stats: { ...words.stats, checkIns: older },
    });
    expect(inLanguage(parsed.awards.crown.title, 'zh-Hant')).toBe('皇冠');
    expect(inLanguage(parsed.stats.checkIns, 'zh-Hant')).toBe('打卡');
    expect(winnerText(parsed, { kind: 'crown', value: 2, language: 'zh-Hant' })).toBe('练了 2 天');
  });

  it('need words for every award and count, and a number in a winner’s', () => {
    const withoutCrown = { planCompleted: award, bestDisclaimer: award };
    expect(WeekSummaryWords.safeParse({ ...words, awards: withoutCrown }).success).toBe(false);
    expect(
      WeekSummaryWords.safeParse({
        ...words,
        awards: {
          ...words.awards,
          crown: { ...award, winner: { ...award.winner, en: counted('a day', '{n}') } },
        },
      }).success,
    ).toBe(false);
    expect(
      WeekSummaryWords.safeParse({ ...words, stats: { ...words.stats, laps: stat } }).success,
    ).toBe(false);
    expect(
      WeekSummaryWords.safeParse({
        ...words,
        awards: { ...words.awards, crown: { ...award, symbol: 'Crown Fill' } },
      }).success,
    ).toBe(false);
  });

  it('need Traditional Chinese in what an admin writes', () => {
    expect(WeekSummaryWordsChange.safeParse({ stats: { checkIns: stat } }).success).toBe(true);
    expect(WeekSummaryWordsChange.safeParse({ stats: { checkIns: older } }).success).toBe(false);
  });
});
