import { describe, expect, it } from 'vitest';

import { containsLink, graphemeCount, mentionsSelfHarm } from './index.js';

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

describe('mentionsSelfHarm', () => {
  it.each(['想自杀', '不想活了', '我不想活', '活不下去', '想自残', '想轻生'])(
    'catches 「%s」',
    (reason) => {
      expect(mentionsSelfHarm(reason)).toBe(true);
    },
  );

  it('catches plain words in English, whatever the case', () => {
    expect(mentionsSelfHarm('I want to KILL MYSELF')).toBe(true);
  });

  it('leaves everyday exaggeration to the model', () => {
    expect(mentionsSelfHarm('加班累得想死')).toBe(false);
  });

  it.each(['今天不想活动', '不想活动筋骨'])(
    'leaves 「%s」 alone: it means not wanting to move',
    (reason) => {
      expect(mentionsSelfHarm(reason)).toBe(false);
    },
  );
});
