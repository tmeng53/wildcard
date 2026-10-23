import { describe, expect, it } from 'vitest';

import { WeekSummaryWords, winnerText } from './week-summary-words.js';

const counted = (one: string, other: string) => ({ one, other });
const award = {
  symbol: 'crown.fill',
  title: { 'zh-Hans': '皇冠', en: 'Crown' },
  winner: {
    'zh-Hans': counted('练了 {n} 天', '练了 {n} 天'),
    en: counted('Trained {n} day', 'Trained {n} days'),
  },
};
const stat = { 'zh-Hans': '打卡', en: 'Check-ins' };
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

describe('the week summary’s words', () => {
  it('count a winner’s value, one or other', () => {
    const parsed = WeekSummaryWords.parse(words);
    expect(winnerText(parsed, { kind: 'crown', value: 1, language: 'en' })).toBe('Trained 1 day');
    expect(winnerText(parsed, { kind: 'crown', value: 5, language: 'en' })).toBe('Trained 5 days');
    expect(winnerText(parsed, { kind: 'crown', value: 0, language: 'zh-Hans' })).toBe('练了 0 天');
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
});
