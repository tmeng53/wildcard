import { describe, expect, it } from 'vitest';

import { UNITS_PER_CHARACTER, containsLink, graphemeCount, typedText } from './index.js';

describe('graphemeCount', () => {
  it.each([
    ['', 0],
    ['腿酸', 2],
    ['abc', 3],
    ['👍🏽', 1],
    ['👨\u200D👩\u200D👧', 1],
    ['🇨🇦', 1],
    ['\u00E9', 1],
  ])('counts %j as %i', (text, count) => {
    expect(graphemeCount(text)).toBe(count);
  });
});

describe('containsLink', () => {
  it.each([
    'https://x.co',
    'HTTP://A',
    'weixin://abc',
    'www.abc',
    'abc.com',
    '看abc.com',
    'ABC.COM/x',
    'a-b.io',
    'abc．com',
    'abc。cn',
    'x.tv冲',
  ])('finds a link in %j', (text) => {
    expect(containsLink(text)).toBe(true);
  });

  it.each(['冲冲冲', 'Mr.Bean', '3.14', '冲!!!🔥', 'a.b', 'go.common', 'abc.comet', '。。。'])(
    'finds no link in %j',
    (text) => {
      expect(containsLink(text)).toBe(false);
    },
  );
});

describe('typedText', () => {
  const text = typedText({
    max: 1000,
    oneLine: false,
    description: 'words',
    rawUnits: 1000 * UNITS_PER_CHARACTER,
  });

  it('takes `max` characters however many UTF-16 units they need', () => {
    const family = '👨\u200D👩\u200D👧\u200D👦';
    expect(text.safeParse('字'.repeat(990) + '👍🏽'.repeat(6)).success).toBe(true);
    expect(text.safeParse(family.repeat(1000)).success).toBe(true);
    expect(text.safeParse(family.repeat(1001)).success).toBe(false);
  });

  it('still refuses a raw body far past any `max` characters', () => {
    expect(text.safeParse('a'.repeat(16_001)).success).toBe(false);
  });
});
