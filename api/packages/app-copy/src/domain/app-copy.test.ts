import { describe, expect, it } from 'vitest';

import { AppCopy, applyChange, fillsLike, formatArguments } from './app-copy.js';

describe('formatArguments', () => {
  it('reads Swift’s interpolations in order, and explicit positions', () => {
    expect([...formatArguments('%@ 练了 %lld 分钟，%lf 公里')]).toEqual([
      [1, '@'],
      [2, 'lld'],
      [3, 'lf'],
    ]);
    expect([...formatArguments('%2$lld minutes by %1$@')]).toEqual([
      [2, 'lld'],
      [1, '@'],
    ]);
    expect([...formatArguments('100%% 完成')]).toEqual([]);
  });
});

describe('fillsLike', () => {
  it('takes words with the same arguments, in any written order', () => {
    expect(fillsLike('还有 %lld 次开门', '再练 %lld 次就开门')).toBe(true);
    expect(fillsLike('%@ 的小队', '%1$@ 的队伍')).toBe(true);
    expect(fillsLike('%@ 练了 %lld 分钟', '%2$lld minutes for %1$@')).toBe(true);
    expect(fillsLike('商店街', '商店街')).toBe(true);
  });

  it('refuses words missing, adding or changing an argument', () => {
    expect(fillsLike('还有 %lld 次开门', '快开门了')).toBe(false);
    expect(fillsLike('商店街', '%@ 的商店街')).toBe(false);
    expect(fillsLike('还有 %lld 次开门', '还有 %@ 次开门')).toBe(false);
  });
});

describe('AppCopy', () => {
  it('refuses a line that drops its key’s placeholder', () => {
    expect(
      AppCopy.safeParse({ version: 1, entries: { '还有 %lld 次开门': { zhHans: '快开门了' } } })
        .success,
    ).toBe(false);
  });

  it('refuses a line with no words', () => {
    expect(AppCopy.safeParse({ version: 1, entries: { 练了: {} } }).success).toBe(false);
  });
});

describe('applyChange', () => {
  it('puts lines over the old ones and takes keys back', () => {
    const copy = AppCopy.parse({
      version: 1,
      entries: { 练了: { zhHans: '训练' }, 商店街: { en: 'Shops' } },
    });
    expect(
      applyChange(copy, { put: { 练了: { zhHans: '练', en: 'Train' } }, takeBack: ['商店街'] }),
    ).toEqual({ version: 1, entries: { 练了: { zhHans: '练', en: 'Train' } } });
  });
});
