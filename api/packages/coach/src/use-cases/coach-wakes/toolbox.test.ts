import { describe, expect, it } from 'vitest';

import { lineProblemAmong } from '../../domain/reply.js';
import { namesOf, userIdIn } from '../../domain/roster.js';

import { challengeTool, mentioning, toolbox, type WakeDraft } from './toolbox.js';

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
    [mia, { name: 'Mia', userId: 'aaaa1111' }],
    [miao, { name: 'Miao', userId: 'bbbb2222' }],
  ]),
};

describe('mentioning', () => {
  it('puts a space after a nickname the line already @s, so the app sees where it ends', () => {
    expect(mentioning({ line: '@Mia加油，@Mia 冲', at: ['aaaa1111'] }, context)).toEqual({
      line: '@Mia 加油，@Mia 冲',
      mentions: [mia],
    });
  });

  it('leaves a longer name that starts with the nickname as it is', () => {
    expect(mentioning({ line: '@Miao加油 @Mia', at: ['aaaa1111'] }, context)).toEqual({
      line: '@Miao加油 @Mia',
      mentions: [mia],
    });
  });

  it('starts the line with the @ when the line leaves it out', () => {
    expect(mentioning({ line: '今天冲', at: ['aaaa1111'] }, context)).toEqual({
      line: '@Mia 今天冲',
      mentions: [mia],
    });
  });
});

describe('a line members read', () => {
  it('holds no user_id in any case, and may say a name whatever it holds', () => {
    const wen = '00000000-0000-4000-8000-000000000003';
    const roster = new Map([...context.roster, [wen, { name: '稳哥', userId: 'cccc3333' }]]);
    const among = { kind: 'reply' as const, names: namesOf(roster) };
    expect(userIdIn(roster, '加油 AAAA1111')).toBe('aaaa1111');
    expect(userIdIn(roster, '加油 Mia')).toBeUndefined();
    expect(lineProblemAmong('@稳哥 今天冲', among)).toBeUndefined();
    expect(lineProblemAmong('@稳哥 稳住', among)).toBe(
      '这句里有「稳」字，教练都不说这个字，换个说法。',
    );
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
      challenges: new Map(),
      gifts: new Map(),
      reply: undefined,
      replyMentions: [],
      reaction: undefined,
      answer: undefined,
      answerMentions: [],
      feedback: undefined,
      steps: [],
    };
    const recall = toolbox({
      week: { ...context.week, weekStart: '2026-11-09', checkIns: [] },
      roster: context.roster,
      coach: 'qifei',
      draft,
      kind: 'checkIn',
      pastWeek: () => Promise.reject(new Error('not read')),
      commentsOf: () => Promise.reject(new Error('not read')),
    }).find(({ name }) => name === 'recall');
    expect(await recall?.run({ path: null, query: '半马 歌' })).toBe(
      '【me.md】- 半马那天我去加油\n【people/aaaa1111.md】- 想跑半马',
    );
    // A file the task lists as still empty is there to look in, never a missing one.
    expect(await recall?.run({ path: 'squad.md', query: null })).toBe(
      '没查到，这些文件还是空的。查不到的就是不记得，别说你记得。',
    );
    // A read: its answer is kept by its length only, since it holds members' words.
    expect(draft.steps).toStrictEqual([
      { tool: 'recall', input: { path: null, query: '半马 歌' }, output: '（44 字）' },
      { tool: 'recall', input: { path: 'squad.md', query: null }, output: '（29 字）' },
    ]);
    expect(draft.changed.size).toBe(0);
  });
});

describe('day_challenge', () => {
  const emptyDraft = (): WakeDraft => ({
    files: new Map(),
    changed: new Set(),
    note: undefined,
    memberNotes: new Map(),
    challenges: new Map(),
    gifts: new Map(),
    reply: undefined,
    replyMentions: [],
    reaction: undefined,
    answer: undefined,
    answerMentions: [],
    feedback: undefined,
    steps: [],
  });
  const tools = (kind: 'checkIn' | 'daily') =>
    toolbox({
      week: { ...context.week, weekStart: '2026-11-09', checkIns: [] },
      roster: context.roster,
      coach: 'qifei',
      draft: emptyDraft(),
      kind,
      pastWeek: () => Promise.reject(new Error('not read')),
      commentsOf: () => Promise.reject(new Error('not read')),
      challenges: () =>
        Promise.resolve([
          {
            day: '2026-11-13',
            member: mia,
            challenge: { title: '吃不同颜色的菜', amount: 5, unit: '种', line: '休息日也能玩' },
            answer: 'accepted' as const,
            reason: undefined,
            completion: undefined,
          },
        ]),
    });

  it('tells a member’s challenge today by user_id, only when a reply looks it up', async () => {
    const lookUp = tools('checkIn').find(({ name }) => name === 'day_challenge');
    expect(await lookUp?.run({ user_id: 'aaaa1111' })).toBe(
      'Mia（aaaa1111） 今天的挑战：吃不同颜色的菜 5 种\n- 挑战卡上的小字：「休息日也能玩」\n- 接了，没记完成',
    );
    expect(await lookUp?.run({ user_id: 'bbbb2222' })).toBe('Miao（bbbb2222） 今天没有挑战。');
    expect(await lookUp?.run({ user_id: 'Mia' })).toBe(
      '没有 user_id 是「Mia」的人。小队的人：Mia（aaaa1111）、Miao（bbbb2222）。',
    );
    // The morning sets the challenges itself; it has no such lookup.
    expect(tools('daily').some(({ name }) => name === 'day_challenge')).toBe(false);
  });
});

describe('set_challenge', () => {
  it('keeps a user_id off the card the member reads', async () => {
    const draft: WakeDraft = {
      files: new Map(),
      changed: new Set(),
      note: undefined,
      memberNotes: new Map(),
      challenges: new Map(),
      gifts: new Map(),
      reply: undefined,
      replyMentions: [],
      reaction: undefined,
      answer: undefined,
      answerMentions: [],
      feedback: undefined,
      steps: [],
    };
    const set = challengeTool(draft, { roster: context.roster, noteTo: [mia] });
    const input = { user_id: 'aaaa1111', recent: '练了两天', needs: '松一松', amount: 10 };
    expect(await set.run({ ...input, title: '拉伸', unit: '分钟', line: '和 bbbb2222 一起' })).toBe(
      '挑战里写了 user_id「bbbb2222」。user_id 只在工具参数里用，给人看的话里只写名字。',
    );
    expect(draft.challenges.size).toBe(0);
    expect(await set.run({ ...input, title: '拉伸', unit: '分钟', line: '昨天你跑得不少' })).toBe(
      '定好了：Mia（aaaa1111）「拉伸 10 分钟」。',
    );
    expect(draft.challenges.get(mia)).toStrictEqual({
      title: '拉伸',
      amount: 10,
      unit: '分钟',
      line: '昨天你跑得不少',
    });
  });
});
