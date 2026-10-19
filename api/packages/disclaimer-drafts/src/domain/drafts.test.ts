import { describe, expect, it } from 'vitest';

import { DraftReason, mentionsSelfHarm } from './draft-request.js';
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
    expect(outcomeOf(drafts([` ${good[0] ?? ''} `, good[1] ?? '', good[2] ?? '']), reason)).toEqual(
      { kind: 'drafts', drafts: good },
    );
  });

  it('turns selfHarm into the care line and unsafe into a decline', () => {
    expect(outcomeOf({ version: 1, outcome: 'selfHarm', drafts: [] }, reason)).toEqual({
      kind: 'care',
    });
    expect(outcomeOf({ version: 1, outcome: 'unsafe', drafts: good }, reason)).toEqual({
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
    ['an emoji', ['闹钟响了三次，我和被子的谈判进入加时赛 😴', good[1] ?? '', good[2] ?? '']],
    ['body talk', ['今天吃太多了胖了一圈，决定原地休息一天。', good[1] ?? '', good[2] ?? '']],
    [
      'the whole reason echoed',
      ['早上没起来，所以今天就先这样吧朋友们。', good[1] ?? '', good[2] ?? ''],
    ],
  ])('fails %s', (_, list) => {
    expect(outcomeOf(drafts(list), reason)).toBeUndefined();
  });

  it('lets a short reason appear as a keyword', () => {
    const rain = DraftReason.parse('下雨了');
    const list = ['下雨了，跑道今天归青蛙使用，我礼让一天。', good[1] ?? '', good[2] ?? ''];
    expect(outcomeOf(drafts(list), rain)?.kind).toBe('drafts');
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
});

describe('mentionsSelfHarm', () => {
  it.each(['想自杀', '不想活了', '活不下去', '想自残', '想轻生'])('catches 「%s」', (reason) => {
    expect(mentionsSelfHarm(DraftReason.parse(reason))).toBe(true);
  });

  it('catches plain words in English, whatever the case', () => {
    expect(mentionsSelfHarm(DraftReason.parse('I want to KILL MYSELF'))).toBe(true);
  });

  it('leaves everyday exaggeration to the model', () => {
    expect(mentionsSelfHarm(DraftReason.parse('加班累得想死'))).toBe(false);
  });
});

describe('promptFor', () => {
  it('names the style in Chinese and lists the memes without examples', () => {
    expect(
      promptFor({
        reason: DraftReason.parse('oncall 到凌晨三点'),
        style: 'heroic',
        memes: [
          {
            phrase: '班味',
            meaning: '上班上出来的疲惫感',
            background: '网友自嘲。',
            styles: ['funny', 'heroic'],
          },
        ],
      }),
    ).toBe(
      [
        '原因：oncall 到凌晨三点',
        '风格：中二',
        '本周梗：',
        '- 梗：班味',
        '  意思：上班上出来的疲惫感',
        '  背景：网友自嘲。',
        '  适合的风格：搞笑、中二',
      ].join('\n'),
    );
  });

  it('leaves the meme line out when there are none', () => {
    expect(promptFor({ reason, style: 'funny', memes: [] })).toBe('原因：早上没起来\n风格：搞笑');
  });
});
