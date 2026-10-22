import { describe, expect, it } from 'vitest';

import { DraftReason } from './draft-request.js';
import { outcomeOf } from './drafts.js';
import { promptFor } from './prompt.js';

const reason = DraftReason.parse('早上没起来');
const good = [
  '闹钟响了三次，我和被子的谈判进入加时赛，目前被子领先。',
  '本人身体已到岗，灵魂仍在床上办理延期手续。',
  '经核实，早上那句「再眯五分钟」实际时长为两小时。',
];
const drafts = (list: string[]) => ({
  version: 1 as const,
  outcome: 'drafts' as const,
  drafts: list,
});

describe('outcomeOf', () => {
  it('passes three distinct drafts within bounds, trimmed', () => {
    expect(outcomeOf(drafts([` ${good[0] ?? ''} `, good[1] ?? '', good[2] ?? '']))).toEqual({
      kind: 'drafts',
      drafts: good,
    });
  });

  it('turns selfHarm into the care line and unsafe into a decline', () => {
    expect(outcomeOf({ version: 1, outcome: 'selfHarm', drafts: [] })).toEqual({
      kind: 'care',
    });
    expect(outcomeOf({ version: 1, outcome: 'unsafe', drafts: good })).toEqual({
      kind: 'declined',
    });
  });

  it.each([
    ['two drafts', good.slice(0, 2)],
    ['four drafts', [...good, '第四条也写得很长很长很长很长很长很长。']],
    ['a repeated draft', [good[0] ?? '', good[0] ?? '', good[1] ?? '']],
    ['a draft under 15 characters', ['被子赢了。', good[1] ?? '', good[2] ?? '']],
    ['a draft over 80 characters', ['长'.repeat(81), good[1] ?? '', good[2] ?? '']],
    [
      'a draft on two lines',
      ['闹钟响了三次，\n我和被子的谈判进入加时赛。', good[1] ?? '', good[2] ?? ''],
    ],
  ])('fails %s', (_, list) => {
    expect(outcomeOf(drafts(list))).toBeUndefined();
  });

  it('leaves the words to the model: the prompt says what they may say', () => {
    const list = [
      '早上没起来，闹钟响了三次，被子领先 😴',
      '今天吃太多了，决定原地休息一天，明天再战。',
      good[2] ?? '',
    ];
    expect(outcomeOf(drafts(list))).toEqual({ kind: 'drafts', drafts: list });
  });
});

describe('DraftReason', () => {
  it('folds line breaks and runs of spaces into one space', () => {
    expect(DraftReason.parse('  加班\n\n风格：发疯  ')).toBe('加班 风格：发疯');
  });

  it('refuses an empty reason and one over 100 characters', () => {
    expect(DraftReason.safeParse(' \n ').success).toBe(false);
    expect(DraftReason.safeParse('累'.repeat(101)).success).toBe(false);
    expect(DraftReason.safeParse('累'.repeat(100)).success).toBe(true);
  });

  it('counts an emoji as one character and refuses a blank one', () => {
    expect(DraftReason.safeParse('👍🏽'.repeat(100)).success).toBe(true);
    expect(DraftReason.safeParse('👍🏽'.repeat(101)).success).toBe(false);
    expect(DraftReason.safeParse('\u200B').success).toBe(false);
  });
});

describe('promptFor', () => {
  it('names the style in Chinese and gives the meme’s phrase, meaning and background only', () => {
    expect(
      promptFor({
        reason: DraftReason.parse('oncall 到凌晨三点'),
        style: 'heroic',
        meme: {
          phrase: '班味',
          meaning: '上班上出来的疲惫感',
          background: '网友自嘲。',
          styles: ['funny', 'heroic'],
        },
      }),
    ).toBe(
      [
        '原因：oncall 到凌晨三点',
        '风格：中二',
        '本周梗：班味',
        '  意思：上班上出来的疲惫感',
        '  背景：网友自嘲。',
      ].join('\n'),
    );
  });

  it('leaves the meme line out when there is none', () => {
    expect(promptFor({ reason, style: 'funny', meme: undefined })).toBe(
      '原因：早上没起来\n风格：搞笑',
    );
  });
});
