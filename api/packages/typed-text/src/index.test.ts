import { describe, expect, it } from 'vitest';

import { containsLink, graphemeCount } from './index.js';

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
