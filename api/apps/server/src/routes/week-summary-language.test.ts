import { describe, expect, it } from 'vitest';

import { languageOf } from './week-summary-language.js';

describe('languageOf', () => {
  it('takes the language the summary is written in that the client weighs highest, Chinese by default', () => {
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
    expect(languageOf('en;q=0.1, zh-Hans;q=1')).toBe('zh-Hans');
    expect(languageOf('fr, en;q=0.5, zh;q=0.5')).toBe('en');
    expect(languageOf('zh;q=abc, en')).toBe('en');
  });
});
