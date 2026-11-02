import { describe, expect, it } from 'vitest';

import { MemeDraft, expiresAfterApproval } from './meme.js';

const city = {
  phrase: ' city不city ',
  background: '外国博主街头问路人「city不city啊」，口音魔性，迅速走红。',
  meaning: '问某事洋不洋气。',
  styles: ['funny'],
  source: '抖音',
};

describe('a meme draft', () => {
  it('is trimmed and kept', () => {
    expect(MemeDraft.parse(city)).toStrictEqual({ ...city, phrase: 'city不city' });
  });

  it('counts characters as people see them, so an emoji is one', () => {
    expect(MemeDraft.safeParse({ ...city, phrase: '👍🏽'.repeat(30) }).success).toBe(true);
  });

  it.each([
    ['no background', { ...city, background: ' ' }],
    ['a phrase of only zero-width spaces', { ...city, phrase: '\u200B\u200B' }],
    ['no styles', { ...city, styles: [] }],
    ['a style twice', { ...city, styles: ['funny', 'funny'] }],
    ['a style the app lacks', { ...city, styles: ['wholesome'] }],
    [
      'example lines, which stay out of the library',
      { ...city, examples: ['今天这雨下得挺 city 的。'] },
    ],
    ['a phrase over 30 characters', { ...city, phrase: '梗'.repeat(31) }],
    ['an unknown field', { ...city, mood: 'chill' }],
  ])('is refused with %s', (_case, input) => {
    expect(MemeDraft.safeParse(input).success).toBe(false);
  });
});

describe('a meme’s expiry', () => {
  const approvedAt = new Date('2026-11-02T18:00:00.000Z');

  it.each([
    { case: 'none', expiresAt: null, allowed: true },
    {
      case: 'a moment after the approval',
      expiresAt: new Date('2026-11-02T18:00:00.001Z'),
      allowed: true,
    },
    { case: 'the approval itself', expiresAt: approvedAt, allowed: false },
    {
      case: 'before the approval',
      expiresAt: new Date('2026-11-01T18:00:00.000Z'),
      allowed: false,
    },
  ])('is allowed for $case: $allowed', ({ expiresAt, allowed }) => {
    expect(expiresAfterApproval(expiresAt, approvedAt)).toBe(allowed);
  });
});
