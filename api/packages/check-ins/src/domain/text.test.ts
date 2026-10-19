import { describe, expect, it } from 'vitest';

import { Caption, CustomSportName, DisclaimerText, graphemeCount } from './text.js';

/** Every Unicode scalar Swift's `.whitespacesAndNewlines` holds (swift:6.0 on Linux). */
const SWIFT_SPACES = [
  0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0x85, 0xa0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004,
  0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
].map((code) => String.fromCodePoint(code));
const LINE_BREAKS = [0x0a, 0x0b, 0x0c, 0x0d, 0x85, 0x2028, 0x2029].map((code) =>
  String.fromCodePoint(code),
);
const ZERO_WIDTH_SPACE = String.fromCodePoint(0x200b);

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

describe('Caption', () => {
  it('trims every space and line break the contract trims, and nothing else', () => {
    const padding = SWIFT_SPACES.join('');
    expect(Caption.parse(`${padding}练完了${padding}`)).toBe('练完了');
    expect(Caption.parse(`${ZERO_WIDTH_SPACE}练完了`)).toBe(`${ZERO_WIDTH_SPACE}练完了`);
    expect(Caption.parse('\uFEFF练完了')).toBe('\uFEFF练完了');
  });

  it('refuses text that is only spaces or zero-width spaces', () => {
    for (const blank of ['', ...SWIFT_SPACES, ZERO_WIDTH_SPACE, ` ${ZERO_WIDTH_SPACE}\u3000`]) {
      expect(Caption.safeParse(blank).success).toBe(false);
    }
  });

  it('takes 60 characters as people count them, not 61', () => {
    expect(Caption.parse('👍🏽'.repeat(60))).toBe('👍🏽'.repeat(60));
    expect(Caption.safeParse('腿'.repeat(61)).success).toBe(false);
  });

  it('refuses each line break inside, but keeps inner spaces', () => {
    expect(LINE_BREAKS.filter((line) => Caption.safeParse(`腿${line}酸`).success)).toStrictEqual(
      [],
    );
    expect(Caption.parse('腿\t酸 了\u3000吧')).toBe('腿\t酸 了\u3000吧');
  });

  it('refuses anything but a string, null included', () => {
    expect(
      [null, undefined, 3, ['a']].map((value) => Caption.safeParse(value).success),
    ).toStrictEqual([false, false, false, false]);
  });
});

describe('DisclaimerText', () => {
  it('may span lines', () => {
    expect(DisclaimerText.parse('\n昨天加班\n今天躺平\n')).toBe('昨天加班\n今天躺平');
  });

  it('refuses more than 40 characters and blank text', () => {
    expect(DisclaimerText.parse('累'.repeat(40))).toBe('累'.repeat(40));
    expect(DisclaimerText.safeParse('累'.repeat(41)).success).toBe(false);
    expect(DisclaimerText.safeParse('\n \n').success).toBe(false);
  });
});

describe('CustomSportName', () => {
  it('takes plain and ideographic spaces inside, up to 20 characters', () => {
    expect(CustomSportName.parse(' 飞盘 高尔夫\u3000 ')).toBe('飞盘 高尔夫');
    expect(CustomSportName.parse('a'.repeat(20))).toBe('a'.repeat(20));
    expect(CustomSportName.safeParse('a'.repeat(21)).success).toBe(false);
  });

  it('refuses tabs, other spaces and control characters inside', () => {
    const inside = ['\t', '\n', '\u00A0', '\u2003', '\u0000', '\u007F'];
    expect(inside.filter((char) => CustomSportName.safeParse(`飞${char}盘`).success)).toStrictEqual(
      [],
    );
  });
});
