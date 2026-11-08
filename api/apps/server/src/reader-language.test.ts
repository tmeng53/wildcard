import { describe, expect, it } from 'vitest';

import { readerLanguageOf } from './reader-language.js';

describe('readerLanguageOf', () => {
  it('takes the app language the client weighs highest, none when it names none', () => {
    expect(readerLanguageOf(undefined)).toBeUndefined();
    expect(readerLanguageOf('ja, fr')).toBeUndefined();
    expect(readerLanguageOf('zh-Hans')).toBe('zh-Hans');
    expect(readerLanguageOf('zh-Hant')).toBe('zh-Hant');
    expect(readerLanguageOf('zh-Hant-TW,en')).toBe('zh-Hant');
    expect(readerLanguageOf('zh-TW')).toBe('zh-Hant');
    expect(readerLanguageOf('zh-HK')).toBe('zh-Hant');
    expect(readerLanguageOf('zh-CN')).toBe('zh-Hans');
    expect(readerLanguageOf('zh')).toBe('zh-Hans');
    expect(readerLanguageOf('en')).toBe('en');
    expect(readerLanguageOf('en;q=0.4, zh-Hant;q=0.9')).toBe('zh-Hant');
    expect(readerLanguageOf('zh-hant;q=0, en')).toBe('en');
  });
});
