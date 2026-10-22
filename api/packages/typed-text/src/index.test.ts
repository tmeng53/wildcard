import { describe, expect, it } from 'vitest';

import { containsLink, graphemeCount, mentionsBodyMetrics } from './index.js';

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

describe('mentionsBodyMetrics', () => {
  it('finds body, calorie and macro words, case-blind', () => {
    for (const text of ['周末体重没变', '热量爆表', 'BMI 正常', '200 kcal', 'Calories']) {
      expect(mentionsBodyMetrics(text)).toBe(true);
    }
  });

  it('lets everything else through', () => {
    expect(mentionsBodyMetrics('周三冒雨跑了 5 公里')).toBe(false);
  });
});
