import { describe, expect, it } from 'vitest';

import {
  editBody,
  FILE_LIMIT,
  shownBody,
  shownPaths,
  squadSeed,
  storedBody,
  storedPathOf,
} from './memory.js';
import { factsText } from './member-facts.js';
import { Coach } from './coach.js';
import { instructionsOf, taskOf } from './prompt.js';
import { lineProblem } from './reply.js';
import { CoachHoliday, holidaysOn, SquadId } from './settings.js';
import { checkInLine, consentedOnly, rosterOf, weekText, type SquadWeek } from './squad-week.js';
import { costMicros, wakesDue, weekStartOf, weeksAround } from './wake.js';

const mia = '11111111-1111-4111-8111-111111111111';
const leo = '22222222-2222-4222-8222-222222222222';
const squad = SquadId.parse('6f1c3e2a-8b4d-4c5e-9f60-7a8b9c0d1e2f');

const week: SquadWeek = {
  weekStart: '2026-10-26',
  members: [{ member: mia, nickname: '米亚' }, { member: leo }],
  checkIns: [
    {
      id: 'c1',
      member: mia,
      day: '2026-10-27',
      createdAt: new Date('2026-10-27T12:00:00Z'),
      kind: 'trained',
      sport: '跑步',
      minutes: 30,
      text: '腿废了',
      reactions: 2,
      comments: [{ id: 'k1', member: leo, text: '强', at: new Date('2026-10-27T12:30:00Z') }],
    },
    {
      id: 'c2',
      member: leo,
      day: '2026-11-01',
      createdAt: new Date('2026-11-01T13:50:00Z'),
      kind: 'disclaimer',
      text: '下雨',
      reactions: 0,
      comments: [],
    },
  ],
};

describe('the squad’s week, as the model reads it', () => {
  it('names members 队员N by the order they joined, never by id', () => {
    const roster = rosterOf(week);
    const [first] = week.checkIns;
    if (first === undefined) throw new Error('no check-in');
    expect([...roster]).toStrictEqual([
      [mia, '队员1'],
      [leo, '队员2'],
    ]);
    expect(checkInLine(first, roster)).toBe(
      '10-27 周二 队员1 训练 跑步 30 分钟 「腿废了」 · 2 个表情 · 评论：队员2「强」',
    );
    expect(weekText(week)).toBe(
      [
        '本周从 2026-10-26（周一）开始。',
        '队员：队员1（昵称：米亚），队员2',
        '打卡：',
        '- 10-27 周二 队员1 训练 跑步 30 分钟 「腿废了」 · 2 个表情 · 评论：队员2「强」',
        '- 11-01 周日 队员2 请假条 「下雨」',
      ].join('\n'),
    );
    expect(weekText(week)).not.toContain(mia);
  });

  it('calls a planned rest 计划休息, not a 请假条', () => {
    const [, leave] = week.checkIns;
    if (leave === undefined) throw new Error('no check-in');
    expect(checkInLine({ ...leave, restDay: true }, rosterOf(week))).toBe(
      '11-01 周日 队员2 计划休息 「下雨」',
    );
  });

  it('keeps only the words of members who agreed to AI use, and the numbering', () => {
    expect(weekText(consentedOnly(week, new Set([leo])))).toBe(
      [
        '本周从 2026-10-26（周一）开始。',
        '队员：队员1，队员2',
        '打卡：',
        '- 11-01 周日 队员2 请假条 「下雨」',
      ].join('\n'),
    );
    expect(weekText(consentedOnly(week, new Set([mia])))).toBe(
      [
        '本周从 2026-10-26（周一）开始。',
        '队员：队员1（昵称：米亚），队员2',
        '打卡：',
        '- 10-27 周二 队员1 训练 跑步 30 分钟 「腿废了」 · 2 个表情',
      ].join('\n'),
    );
  });

  it('names the squad, and says when a check-in was posted days after the day it counts for', () => {
    const [first] = week.checkIns;
    if (first === undefined) throw new Error('no check-in');
    const backdated = { ...first, comments: [], reactions: 0, postedDay: '2026-10-29' };
    expect(checkInLine(backdated, rosterOf(week))).toBe(
      '10-27 周二 队员1 训练 （补打卡：10-29 周四 才发） 跑步 30 分钟 「腿废了」',
    );
    expect(weekText({ ...week, name: '周末不睡懒觉', checkIns: [] })).toBe(
      [
        '队名：周末不睡懒觉',
        '本周从 2026-10-26（周一）开始。',
        '队员：队员1（昵称：米亚），队员2',
        '这周还没有人打卡。',
      ].join('\n'),
    );
    // A member without AI consent keeps the squad's name, but not their nickname.
    expect(consentedOnly({ ...week, name: '周末不睡懒觉' }, new Set([leo])).name).toBe(
      '周末不睡懒觉',
    );
  });
});

describe('the memory files', () => {
  it('stores members named in a file by id, and shows them by their name now', () => {
    const roster = rosterOf(week);
    const stored = storedBody('队员1 爱跑步，队员2 怕雨，队员12 不存在', roster);
    expect(stored).toBe(`{队员:${mia}} 爱跑步，{队员:${leo}} 怕雨，队员12 不存在`);
    expect(shownBody(stored, roster)).toBe('队员1 爱跑步，队员2 怕雨，队员12 不存在');
    // 米亚 left: 队员1 is 里奥 now, and 米亚 is no one's number.
    const after = rosterOf({ ...week, members: [{ member: leo }] });
    expect(shownBody(stored, after)).toBe('一位已离队的队员 爱跑步，队员1 怕雨，队员12 不存在');
  });

  const roster = rosterOf(week);

  it('show each member’s page by roster name and store it by member id', () => {
    expect(shownPaths(roster)).toStrictEqual([
      'squad.md',
      'memory.md',
      'people/队员1.md',
      'people/队员2.md',
    ]);
    expect(storedPathOf('people/队员2.md', roster)).toBe(`people/${leo}.md`);
    expect(storedPathOf('memory.md', roster)).toBe('memory.md');
    expect(storedPathOf('people/队员3.md', roster)).toBeUndefined();
    expect(storedPathOf(`people/${mia}.md`, roster)).toBeUndefined();
    expect(storedPathOf('../secrets.md', roster)).toBeUndefined();
  });

  it('start a squad’s file from its name and who is in it', () => {
    expect(squadSeed({ ...week, name: '周末不睡懒觉' }, rosterOf(week))).toBe(
      [
        '# 小队',
        '队名：周末不睡懒觉',
        '队员（昵称会变，以 squad_week 为准）：',
        '- 队员1：昵称「米亚」',
        '- 队员2',
      ].join('\n'),
    );
  });

  it('edit by replacing text found once, or adding at the end', () => {
    expect(editBody('', { find: '', replace: '- 米亚爱跑步' })).toStrictEqual({
      ok: true,
      body: '- 米亚爱跑步',
    });
    expect(editBody('- 米亚爱跑步\n\n', { find: '', replace: '- 队员2怕雨' })).toStrictEqual({
      ok: true,
      body: '- 米亚爱跑步\n- 队员2怕雨',
    });
    expect(editBody('- 米亚爱跑步', { find: '跑步', replace: '夜跑' })).toStrictEqual({
      ok: true,
      body: '- 米亚爱夜跑',
    });
    expect(editBody('跑步 跑步', { find: '跑步', replace: '' })).toMatchObject({ ok: false });
    expect(editBody('游泳', { find: '跑步', replace: '' })).toMatchObject({ ok: false });
    expect(editBody('', { find: '', replace: 'x'.repeat(FILE_LIMIT + 1) })).toMatchObject({
      ok: false,
    });
  });
});

describe('when the coach wakes', () => {
  it('finds the Monday of a day’s week', () => {
    expect(weekStartOf('2026-11-01')).toBe('2026-10-26');
    expect(weekStartOf('2026-10-26')).toBe('2026-10-26');
  });

  it('looks in every week a member’s own day can be in', () => {
    // 10am Sunday in New York is already Monday east of UTC+10.
    expect(weeksAround(new Date('2026-11-01T15:00:00Z'))).toStrictEqual([
      '2026-10-26',
      '2026-11-02',
    ]);
    // 1am Monday in New York is still Sunday in Hawaii.
    expect(weeksAround(new Date('2026-11-02T06:00:00Z'))).toStrictEqual([
      '2026-10-26',
      '2026-11-02',
    ]);
    expect(weeksAround(new Date('2026-11-04T17:00:00Z'))).toStrictEqual(['2026-11-02']);
  });

  it('wakes for check-ins of the last hour, and once a day from 6am on the squad’s clock', () => {
    // 10:00 EST: c2 was made 10 minutes ago, c1 days ago.
    expect(
      wakesDue({
        squad,
        week,
        now: new Date('2026-11-01T14:00:00Z'),
        timeZone: 'America/New_York',
      }),
    ).toStrictEqual([
      { squad, reason: { kind: 'checkIn', checkIn: 'c2' } },
      { squad, reason: { kind: 'daily', day: '2026-11-01' } },
    ]);
    // 6:00 in Taipei is 17:00 the day before in New York: the squad's own clock.
    expect(
      wakesDue({ squad, week, now: new Date('2026-10-31T22:00:00Z'), timeZone: 'Asia/Taipei' }),
    ).toStrictEqual([{ squad, reason: { kind: 'daily', day: '2026-11-01' } }]);
    // 5:59 EST: no daily wake yet.
    expect(
      wakesDue({
        squad,
        week,
        now: new Date('2026-11-01T10:59:00Z'),
        timeZone: 'America/New_York',
      }),
    ).toStrictEqual([]);
  });

  it('wakes for replies to the coach of the last hour, even under an older check-in', () => {
    const [c1, c2] = week.checkIns;
    if (c1 === undefined || c2 === undefined) throw new Error('no check-ins');
    const replied: SquadWeek = {
      ...week,
      checkIns: [
        {
          ...c1,
          comments: [
            ...c1.comments,
            {
              id: 'k2',
              member: leo,
              text: '教练你说谁',
              at: new Date('2026-11-01T13:55:00Z'),
              toCoach: 'xiaohun',
            },
            // A reply to a member, not the coach: nothing to wake for.
            { id: 'k3', member: mia, text: '说你', at: new Date('2026-11-01T13:56:00Z') },
          ],
        },
        c2,
      ],
    };
    expect(
      wakesDue({
        squad,
        week: replied,
        now: new Date('2026-11-01T14:00:00Z'),
        timeZone: 'America/New_York',
      }),
    ).toStrictEqual([
      { squad, reason: { kind: 'checkIn', checkIn: 'c2' } },
      { squad, reason: { kind: 'comment', checkIn: 'c1', comment: 'k2' } },
      { squad, reason: { kind: 'daily', day: '2026-11-01' } },
    ]);
    // Two hours on, it is the coach job's no more: it was answered when written, or never.
    expect(
      wakesDue({
        squad,
        week: replied,
        now: new Date('2026-11-01T16:00:00Z'),
        timeZone: 'America/New_York',
      }),
    ).toStrictEqual([{ squad, reason: { kind: 'daily', day: '2026-11-01' } }]);
  });

  it('gives a reply’s wake the talk under the check-in, the reply to answer marked', () => {
    const task = taskOf({
      reason: { kind: 'comment', checkIn: 'c1', comment: 'k2' },
      week,
      files: new Map([['memory.md', undefined]]),
      recentNotes: [],
      thread: {
        reply: '腿废了也算练',
        said: [
          { member: leo, text: '教练你也跑吗' },
          { member: undefined, text: '我负责喊' },
          { member: mia, text: '那你喊大声点', answering: true },
        ],
      },
    });
    expect(task).toBe(
      [
        '有人回复你。这条打卡：10-27 周二 队员1 训练 跑步 30 分钟 「腿废了」 · 2 个表情',
        // The rest of the post's comments, so the coach knows what was said around it.
        '这条下面别人的评论（先后顺序）：\n- 队员2：「强」',
        '你们在下面的对话：\n- 你：「腿废了也算练」\n- 队员2：「教练你也跑吗」\n- 你：「我负责喊」\n- 队员1：「那你喊大声点」（要回的这句）',
        '你的记性（你只记得这些）：\n还是空的：memory.md',
      ].join('\n\n'),
    );
    // A post with photos: the coach is told it hasn't seen them, so it looks before answering
    // what they show instead of guessing from the words (and only when it can look).
    const withPhotos: SquadWeek = {
      ...week,
      checkIns: week.checkIns.map((each) =>
        each.id === 'c1' ? { ...each, photos: ['m/a.jpg', 'm/b.jpg'] } : each,
      ),
    };
    const asked = {
      reason: { kind: 'comment', checkIn: 'c1', comment: 'k2' },
      week: withPhotos,
      files: new Map(),
      recentNotes: [],
      thread: { said: [{ member: mia, text: '你看看我吃了啥', answering: true }] },
    } as const;
    expect(taskOf({ ...asked, canSeePhotos: true })?.split('\n\n')).toContain(
      '这条打卡有 2 张照片，你还没看过。要回的这句问到照片里的东西，就先用 look_at_photos 看。',
    );
    expect(taskOf(asked)).not.toContain('look_at_photos');
    // On a holiday the coach is told, after the talk and before its files.
    expect(
      taskOf({
        reason: { kind: 'checkIn', checkIn: 'c1' },
        week,
        files: new Map(),
        recentNotes: [],
        occasions: ['感恩节', 'TURKEY TROT 限时开张'],
      })?.split('\n\n')[1],
    ).toBe('今天：感恩节、TURKEY TROT 限时开张');
    // Without the talk, or once the check-in left the week, there is nothing to answer.
    expect(
      taskOf({
        reason: { kind: 'comment', checkIn: 'c1', comment: 'k2' },
        week,
        files: new Map(),
        recentNotes: [],
      }),
    ).toBeUndefined();
  });

  it('counts a wake’s cost at the settings’ prices, cached input at its own, rounded up', () => {
    const prices = {
      inputMicrosPerMillion: 100_000,
      cachedInputMicrosPerMillion: 10_000,
      outputMicrosPerMillion: 500_000,
    };
    // GPT-6 Luna: 2,000 uncached in at $0.10, 10,000 cached at $0.01, 800 out at $0.50.
    expect(
      costMicros(
        { requests: 3, inputTokens: 12_000, cachedInputTokens: 10_000, outputTokens: 800 },
        prices,
      ),
    ).toBe(200 + 100 + 400);
    // Nothing cached: every input token at the full price.
    expect(
      costMicros(
        { requests: 3, inputTokens: 12_000, cachedInputTokens: 0, outputTokens: 800 },
        prices,
      ),
    ).toBe(1_200 + 400);
    expect(
      costMicros(
        { requests: 1, inputTokens: 1, cachedInputTokens: 0, outputTokens: 0 },
        { inputMicrosPerMillion: 1, cachedInputMicrosPerMillion: 0, outputMicrosPerMillion: 0 },
      ),
    ).toBe(1);
  });

  it('lets the coach pick its tools, keep memory any time, and say one thing per note', () => {
    const coach = Coach.parse({
      version: 3,
      id: 'nuannuan',
      position: 2,
      tier: 'entry',
      name: '暖暖',
      title: '暖心教练',
      catchphrase: '今天也辛苦啦',
      background: '普拉提教练',
      yearsCoaching: 6,
      experience: '夸人满分',
      tags: ['温柔'],
      pay: '一杯奶茶',
      style: '温柔',
      soul: '你是暖暖。',
      look: 'nuannuan',
      offered: true,
    });
    const instructions = instructionsOf({ rules: '规矩' }, coach);
    expect(instructions).toContain('一张便条只说一件事');
    expect(instructions).toContain('做什么、用哪个工具，你自己判断。');
    // The old rule had every note add something from memory, which made notes say "I remember".
    expect(instructions).not.toContain('再加上记性里记着他的');
  });

  it('keeps what every wake begins with in the instructions, and only what changes in the task', () => {
    const task = taskOf({
      reason: { kind: 'daily', day: '2026-11-01' },
      week,
      files: new Map([
        ['memory.md', '米亚爱跑步'],
        ['squad.md', undefined],
      ]),
      recentNotes: [{ day: '2026-10-31', text: '周末也要动一动' }],
    });
    expect(task).toBe(
      [
        '新的一天：2026-11-01，周日。',
        '过去一天没人在打卡下面和你说话。',
        // What it remembers, in full: it forgets everything else between wakes.
        '你的记性（你只记得这些）：\n【memory.md】\n米亚爱跑步\n还是空的：squad.md',
        '你最近写过：\n- 2026-10-31：周末也要动一动',
        // The 战术板 in the squad's language: Simplified Chinese until the week says another.
        '战术板：用简体中文写。',
        '今天没有要写便条的人。',
      ].join('\n\n'),
    );
    // A holiday's morning: told right after the day.
    expect(
      taskOf({
        reason: { kind: 'daily', day: '2026-11-26' },
        week,
        files: new Map(),
        recentNotes: [],
        occasions: ['感恩节'],
      })
        ?.split('\n\n')
        .slice(0, 2),
    ).toStrictEqual(['新的一天：2026-11-26，周四。', '今天：感恩节']);
    // Whom it writes a morning note to, by the names it knows them by.
    expect(
      taskOf({
        reason: { kind: 'daily', day: '2026-11-01' },
        week,
        files: new Map(),
        recentNotes: [],
        noteTo: [
          {
            name: '队员1',
            trainedDays: 2,
            plan: { today: { kind: 'train', sport: '游泳' }, fuelGoals: ['喝够水', '少吃外卖'] },
          },
          { name: '队员2', trainedDays: 0, plan: { today: { kind: 'rest' }, fuelGoals: [] } },
          // Plans that couldn't be read: only the days trained.
          { name: '队员3', trainedDays: 1 },
        ],
      })
        ?.split('\n\n')
        .at(-1),
    ).toBe(
      [
        '今天给这些人各写一张便条：',
        '- 队员1：今天出赛表排了游泳；这周的饮食小目标：喝够水、少吃外卖；这周已经练了 2 天。',
        '- 队员2：今天出赛表是休息日；这周没定饮食小目标；这周已经练了 0 天。',
        '- 队员3：这周已经练了 1 天。',
      ].join('\n'),
    );
    // Yesterday's posts, for the notes to pick up on, and a day nobody posted.
    const [posted] = week.checkIns;
    if (posted === undefined) throw new Error('no check-in');
    expect(
      taskOf({
        reason: { kind: 'daily', day: '2026-10-28' },
        week,
        files: new Map(),
        recentNotes: [],
        yesterday: { day: '2026-10-27', checkIns: [posted] },
      })?.split('\n\n')[1],
    ).toBe(
      '昨天（周二）小队的动态：\n- 10-27 周二 队员1 训练 跑步 30 分钟 「腿废了」 · 2 个表情 · 评论：队员2「强」',
    );
    expect(
      taskOf({
        reason: { kind: 'daily', day: '2026-10-29' },
        week,
        files: new Map(),
        recentNotes: [],
        yesterday: { day: '2026-10-28', checkIns: [] },
      })?.split('\n\n')[1],
    ).toBe('昨天（周三）小队没人发动态。');
    // The last day's talk under check-ins, for it to remember from.
    const [first] = week.checkIns;
    if (first === undefined) throw new Error('no check-in');
    expect(
      taskOf({
        reason: { kind: 'daily', day: '2026-11-01' },
        week,
        files: new Map([['memory.md', undefined]]),
        recentNotes: [],
        talks: [
          {
            checkIn: first,
            reply: '腿废了也算练',
            said: [
              { member: leo, text: '我下周膝盖手术' },
              { member: undefined, text: '那这周先歇着' },
            ],
          },
        ],
      })?.split('\n\n')[1],
    ).toBe(
      '过去一天打卡下面的对话（先后顺序）：\n- 10-27 周二 队员1 训练 跑步 30 分钟 「腿废了」 · 2 个表情\n  你：「腿废了也算练」\n  队员2：「我下周膝盖手术」\n  你：「那这周先歇着」',
    );
    expect(
      taskOf({
        reason: { kind: 'checkIn', checkIn: 'c2' },
        week,
        files: new Map([['memory.md', undefined]]),
        recentNotes: [],
      }),
    ).toBe(
      '有人打卡：11-01 周日 队员2 请假条 「下雨」\n\n你最近没点过表情。\n\n用简体中文写。\n\n你的记性（你只记得这些）：\n还是空的：memory.md',
    );
    // The emoji it reacted with lately, so it varies them.
    expect(
      taskOf({
        reason: { kind: 'checkIn', checkIn: 'c2' },
        week,
        files: new Map([['memory.md', undefined]]),
        recentNotes: [],
        recentEmoji: ['🔥', '🔥', '💪'],
      }),
    ).toBe(
      '有人打卡：11-01 周日 队员2 请假条 「下雨」\n\n你最近点过的表情（新的在前）：🔥 🔥 💪\n\n用简体中文写。\n\n你的记性（你只记得这些）：\n还是空的：memory.md',
    );
  });

  it('writes what one member reads in their language, and the 战术板 in the squad’s', () => {
    const multilingual: SquadWeek = {
      ...week,
      members: [
        { member: mia, nickname: '米亚', language: 'zh-Hant' },
        { member: leo, language: 'en' },
      ],
      language: 'zh-Hant',
    };
    // A check-in's reply in its author's language (队员2 posted c2).
    expect(
      taskOf({
        reason: { kind: 'checkIn', checkIn: 'c2' },
        week: multilingual,
        files: new Map(),
        recentNotes: [],
      })?.split('\n\n'),
    ).toContain('Write in English.');
    const daily = taskOf({
      reason: { kind: 'daily', day: '2026-11-01' },
      week: multilingual,
      files: new Map(),
      recentNotes: [],
      noteTo: [
        { name: '队员1', language: 'zh-Hant', trainedDays: 1 },
        { name: '队员2', language: 'en', trainedDays: 0 },
      ],
    })?.split('\n\n');
    expect(daily).toContain('战术板：用繁體中文寫，照台灣的說法。');
    expect(daily?.at(-1)).toBe(
      [
        '今天给这些人各写一张便条：',
        '- 队员1：这周已经练了 1 天。 用繁體中文寫，照台灣的說法。',
        '- 队员2：这周已经练了 0 天。 Write in English.',
      ].join('\n'),
    );
  });

  it('has nothing to do for a check-in no longer in the week', () => {
    const files = new Map([['memory.md', undefined]]);
    expect(
      taskOf({ reason: { kind: 'checkIn', checkIn: 'gone' }, week, files, recentNotes: [] }),
    ).toBeUndefined();
    expect(
      taskOf({ reason: { kind: 'checkIn', checkIn: 'c2' }, week, files, recentNotes: [] }),
    ).toContain('11-01 周日 队员2 请假条 「下雨」');
    expect(
      taskOf({
        reason: { kind: 'daily', day: '2026-11-01' },
        week,
        files: new Map([['memory.md', '米亚爱跑步']]),
        recentNotes: [{ day: '2026-10-31', text: '周末也要动一动' }],
      }),
    ).toContain('- 2026-10-31：周末也要动一动');
  });
});

describe('the holiday calendar', () => {
  const calendar = [
    { date: '12-25', name: '圣诞节' },
    { date: '2026-11-26', name: '感恩节' },
    { date: '2027-11-25', name: '感恩节' },
    { date: '11-26', name: '某个每年的日子' },
  ];

  it('names the day’s holidays, every year’s and that year’s, in the calendar’s order', () => {
    expect(holidaysOn(calendar, '2026-12-25')).toStrictEqual(['圣诞节']);
    expect(holidaysOn(calendar, '2031-12-25')).toStrictEqual(['圣诞节']);
    expect(holidaysOn(calendar, '2026-11-26')).toStrictEqual(['感恩节', '某个每年的日子']);
    // A holiday that moves is only on the year it names.
    expect(holidaysOn(calendar, '2027-11-26')).toStrictEqual(['某个每年的日子']);
    expect(holidaysOn(calendar, '2027-11-25')).toStrictEqual(['感恩节']);
    expect(holidaysOn(calendar, '2026-11-25')).toStrictEqual([]);
  });

  it('takes a day and a one-line name, nothing else', () => {
    expect(CoachHoliday.safeParse({ date: '13-01', name: '无' }).success).toBe(false);
    expect(CoachHoliday.safeParse({ date: '2026-1-01', name: '无' }).success).toBe(false);
    // Only days that exist: 02-29 every leap year, never 02-30 or 2026-02-29.
    expect(CoachHoliday.safeParse({ date: '02-30', name: '无' }).success).toBe(false);
    expect(CoachHoliday.safeParse({ date: '04-31', name: '无' }).success).toBe(false);
    expect(CoachHoliday.safeParse({ date: '2026-02-29', name: '无' }).success).toBe(false);
    expect(CoachHoliday.safeParse({ date: '02-29', name: '闰日' }).success).toBe(true);
    expect(CoachHoliday.safeParse({ date: '2028-02-29', name: '闰日' }).success).toBe(true);
    expect(CoachHoliday.safeParse({ date: '01-01', name: ' ' }).success).toBe(false);
    expect(CoachHoliday.safeParse({ date: '01-01', name: '元旦\n快乐' }).success).toBe(false);
    expect(CoachHoliday.parse({ date: '01-01', name: ' 元旦 ' })).toStrictEqual({
      date: '01-01',
      name: '元旦',
    });
  });
});

describe('what the coach looks up', () => {
  it('reads each member’s counts, titles and this week’s plan, and how many photos a post has', () => {
    const rest = { kind: 'rest' } as const;
    expect(
      factsText(
        [
          {
            member: mia,
            trainedDays: 50,
            healthyMeals: 3,
            cheatMeals: 1,
            disclaimers: 2,
            topSport: { name: '跑步', checkIns: 31 },
            titles: 2,
            latestTitle: '早起之王',
            plan: [
              { kind: 'train', sport: '跑步' },
              rest,
              { kind: 'train' },
              rest,
              rest,
              rest,
              rest,
            ],
            fuelGoals: ['喝够水', '奶茶减半'],
          },
          {
            member: leo,
            trainedDays: 0,
            healthyMeals: 0,
            cheatMeals: 0,
            disclaimers: 0,
            titles: 0,
            plan: [rest, rest, rest, rest, rest, rest, rest],
            fuelGoals: [],
          },
        ],
        rosterOf(week),
      ),
    ).toBe(
      [
        '队员1：一共练了 50 天，健康餐 3 次，坦白放纵餐 1 次，请假条 2 次。最常练跑步（31 次）。拿过 2 个周奖，最近一个是「早起之王」。',
        '本周出赛表：周一跑步，周二休息，周三练，周四休息，周五休息，周六休息，周日休息。这周的饮食小目标：喝够水、奶茶减半。',
        '队员2：一共练了 0 天，健康餐 0 次，坦白放纵餐 0 次，请假条 0 次。还没拿过周奖。',
        '本周出赛表：周一休息，周二休息，周三休息，周四休息，周五休息，周六休息，周日休息。这周没定饮食小目标。',
      ].join('\n'),
    );
    expect(factsText([], rosterOf(week))).toBe('还没有队员的数据。');
    const [first] = week.checkIns;
    if (first === undefined) throw new Error('no check-in');
    expect(
      checkInLine({ ...first, photos: ['a.jpg', 'b.jpg'], comments: [] }, rosterOf(week)),
    ).toBe('10-27 周二 队员1 训练 跑步 30 分钟 「腿废了」 （2 张照片） · 2 个表情');
  });
});

describe('a line members read', () => {
  it('never names anyone as 队员N, however the number is written', () => {
    const named = '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。';
    expect(
      ['队员1 加油', '队员 3 加油', '队员３加油'].map((line) => lineProblem(line, 100)),
    ).toStrictEqual([named, named, named]);
    expect(lineProblem('全体队员加油', 100)).toBeUndefined();
    expect(lineProblem('跑跑跑', 2)).toBe('太长了：3 字，最多 2 字。');
    expect(lineProblem('', 2)).toBe('这句是空的。');
  });
});
