import { describe, expect, it } from 'vitest';

import { MemeDraft, inUseSince } from './meme.js';

const city = {
  phrase: ' city不city ',
  background: '外国博主街头问路人「city不city啊」，口音魔性，迅速走红。',
  meaning: '问某事洋不洋气。',
  styles: ['funny'],
  source: '抖音',
  examples: ['今天这雨下得挺 city 的，我选择在家感受。'],
};

describe('a meme draft', () => {
  it('is trimmed and kept', () => {
    expect(MemeDraft.parse(city)).toStrictEqual({ ...city, phrase: 'city不city' });
  });

  it.each([
    ['no background', { ...city, background: ' ' }],
    ['no styles', { ...city, styles: [] }],
    ['a style twice', { ...city, styles: ['funny', 'funny'] }],
    ['a style the app lacks', { ...city, styles: ['wholesome'] }],
    ['no examples', { ...city, examples: [] }],
    ['six examples', { ...city, examples: ['一', '二', '三', '四', '五', '六'] }],
    ['a phrase over 30 characters', { ...city, phrase: '梗'.repeat(31) }],
    ['an unknown field', { ...city, calories: 300 }],
  ])('is refused with %s', (_case, input) => {
    expect(MemeDraft.safeParse(input).success).toBe(false);
  });
});

describe('memes in use', () => {
  it('go back 28 days', () => {
    expect(inUseSince(new Date('2026-11-16T16:00:00.000Z'))).toStrictEqual(
      new Date('2026-10-19T16:00:00.000Z'),
    );
  });
});
