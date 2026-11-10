import { describe, expect, it } from 'vitest';

import { mentioning, toolbox, type WakeDraft } from './toolbox.js';

const mia = '00000000-0000-4000-8000-000000000001';
const miao = '00000000-0000-4000-8000-000000000002';
const context = {
  week: {
    members: [
      { member: mia, nickname: 'Mia' },
      { member: miao, nickname: 'Miao' },
    ],
  },
  roster: new Map([
    [mia, '队员1'],
    [miao, '队员2'],
  ]),
};

describe('mentioning', () => {
  it('puts a space after a nickname the line already @s, so the app sees where it ends', () => {
    expect(mentioning({ line: '@Mia加油，@Mia 冲', at: ['队员1'] }, context)).toEqual({
      line: '@Mia 加油，@Mia 冲',
      mentions: [mia],
    });
  });

  it('leaves a longer name that starts with the nickname as it is', () => {
    expect(mentioning({ line: '@Miao加油 @Mia', at: ['队员1'] }, context)).toEqual({
      line: '@Miao加油 @Mia',
      mentions: [mia],
    });
  });

  it('starts the line with the @ when the line leaves it out', () => {
    expect(mentioning({ line: '今天冲', at: ['队员1'] }, context)).toEqual({
      line: '@Mia 今天冲',
      mentions: [mia],
    });
  });
});

describe('recall', () => {
  it('looks up the files as the model names them, never another coach’s page', async () => {
    const draft: WakeDraft = {
      files: new Map([
        [`people/${mia}.md`, '- 对花生过敏\n- 想跑半马'],
        ['coaches/maotou.md', '- 我答应过队员1 一首歌'],
        ['coaches/qifei.md', '- 半马那天我去加油'],
        ['memory.md', '- 大家约好周日爬山'],
      ]),
      changed: new Set(),
      note: undefined,
      memberNotes: new Map(),
      gifts: new Map(),
      reply: undefined,
      replyMentions: [],
      reaction: undefined,
      answer: undefined,
      answerMentions: [],
      challengeDone: false,
      steps: [],
    };
    const recall = toolbox({
      week: { ...context.week, weekStart: '2026-11-09', checkIns: [] },
      roster: context.roster,
      coach: 'qifei',
      draft,
      kind: 'checkIn',
    }).find(({ name }) => name === 'recall');
    expect(await recall?.run({ query: '半马 歌' })).toBe(
      '【people/队员1.md】- 想跑半马\n【me.md】- 半马那天我去加油',
    );
    // A read: its answer is kept by its length only, since it holds members' words.
    expect(draft.steps).toStrictEqual([
      { tool: 'recall', input: { query: '半马 歌' }, output: '（39 字）' },
    ]);
    expect(draft.changed.size).toBe(0);
  });
});
