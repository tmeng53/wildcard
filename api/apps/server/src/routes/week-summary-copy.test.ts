import { describe, expect, it } from 'vitest';

import { AWARD_COPY, languageOf } from './week-summary-copy.js';

describe('languageOf', () => {
  it('takes the first language the summary is written in, Chinese by default', () => {
    expect(languageOf(undefined)).toBe('zh-Hans');
    expect(languageOf('')).toBe('zh-Hans');
    expect(languageOf('fr-FR, en;q=0.8')).toBe('en');
    expect(languageOf('zh-Hant-TW,en')).toBe('zh-Hans');
    expect(languageOf('EN-gb')).toBe('en');
    expect(languageOf('ja, fr')).toBe('zh-Hans');
    expect(languageOf('en;q=0, zh')).toBe('zh-Hans');
    expect(languageOf('en;q=0.000, fr')).toBe('zh-Hans');
    expect(languageOf('en;q=0.5')).toBe('en');
    expect(languageOf('zha, enm, en')).toBe('en');
  });
});

describe('award copy', () => {
  it('counts days and reactions in each language', () => {
    expect(AWARD_COPY.crown.winner(5)).toEqual({ 'zh-Hans': '练了 5 天', en: 'Trained 5 days' });
    expect(AWARD_COPY.bestDisclaimer.winner(2)).toEqual({
      'zh-Hans': '2 个回应',
      en: '2 reactions',
    });
  });
});
