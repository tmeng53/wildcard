import { describe, expect, it } from 'vitest';

import {
  CoachFilePath,
  editBody,
  FILE_LIMIT,
  shownBody,
  shownPathOf,
  shownPaths,
  squadSeed,
  storedBody,
  storedPathOf,
  recallLines,
  sliceWhole,
  RECALL_LIMIT,
} from './memory.js';
import { factsText } from './member-facts.js';
import { Coach } from './coach.js';
import { lineLanguageOf, longestLine } from './line-limits.js';
import { HEAD_LIMIT, instructionsOf, memoryIndex, saidLines, taskOf } from './prompt.js';
import { lineProblem } from './reply.js';
import { CoachHoliday, holidaysOn, SquadId } from './settings.js';
import { checkInBlock, consentedOnly, rosterOf, weekText, type SquadWeek } from './squad-week.js';
import { wakesDue, weeksAround } from './wake.js';

const mia = '11111111-1111-4111-8111-111111111111';
const leo = '22222222-2222-4222-8222-222222222222';
const squad = SquadId.parse('6f1c3e2a-8b4d-4c5e-9f60-7a8b9c0d1e2f');

/** The task's `## ` section that starts with `heading`, with everything under it. */
function section(task: string | undefined, heading: string): string | undefined {
  return (task ?? '').split(/\n\n(?=## )/).find((part) => part.startsWith(heading));
}

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
      reactedBy: [leo],
      comments: [{ id: 'k1', member: leo, text: '强', at: new Date('2026-10-27T12:30:00Z') }],
    },
    {
      id: 'c2',
      member: leo,
      day: '2026-11-01',
      createdAt: new Date('2026-11-01T13:50:00Z'),
      kind: 'disclaimer',
      text: '下雨',
      reactedBy: [],
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
    expect(weekText(week)).toBe(
      [
        '# 本周',
        '- 从 2026-10-26（周一）开始',
        '',
        '## 谁是谁（队员N：昵称）',
        '- 队员1：米亚',
        '- 队员2',
        '',
        '## 打卡',
        '',
        '### 10-27 周二 · 队员1 · 训练：跑步 30 分钟',
        '- 写的：「腿废了」',
        '- 点了表情：队员2',
        '- 评论（先后顺序）：',
        '  - 队员2：「强」',
        '',
        '### 11-01 周日 · 队员2 · 请假条',
        '- 写的：「下雨」',
      ].join('\n'),
    );
    expect(weekText(week)).not.toContain(mia);
  });

  it('names the place a post was tagged with', () => {
    const [first] = week.checkIns;
    if (first === undefined) throw new Error('no check-in');
    expect(
      checkInBlock(
        { ...first, place: 'Equinox Flatiron', comments: [] },
        { roster: rosterOf(week) },
      ),
    ).toBe(
      '### 10-27 周二 · 队员1 · 训练：跑步 30 分钟\n- 地点：「Equinox Flatiron」\n- 写的：「腿废了」\n- 点了表情：队员2',
    );
  });

  it('says whom each comment replies to and @s, a teammate or the coach', () => {
    const roster = rosterOf(week);
    const [first] = week.checkIns;
    if (first === undefined) throw new Error('no check-in');
    const comments = [
      { id: 'k1', member: leo, text: '强', at: new Date(0) },
      { id: 'k2', member: mia, text: '你也来', at: new Date(0), replyTo: leo },
      { id: 'k3', member: leo, text: '看', at: new Date(0), mentions: [mia], mentionsCoach: 'mao' },
      { id: 'k4', member: mia, text: '谢谢', at: new Date(0), toCoach: 'mao' },
    ];
    expect(checkInBlock({ ...first, reactedBy: [], comments }, { roster })).toBe(
      [
        '### 10-27 周二 · 队员1 · 训练：跑步 30 分钟',
        '- 写的：「腿废了」',
        '- 评论（先后顺序）：',
        '  - 队员2：「强」',
        '  - 队员1（回复队员2）：「你也来」',
        '  - 队员2（@队员1，@你）：「看」',
        '  - 队员1（回复你）：「谢谢」',
      ].join('\n'),
    );
    expect(
      saidLines(
        [
          { by: { member: mia }, text: '你也来', replyTo: leo },
          {
            by: { member: leo },
            text: '看',
            mentions: [mia],
            to: { kind: 'mention', coach: '你' },
          },
        ],
        roster,
      ),
    ).toStrictEqual(['- 队员1（回复队员2）：「你也来」', '- 队员2（@队员1，@你）：「看」']);
  });

  it('calls a planned rest 计划休息, not a 请假条', () => {
    const [, leave] = week.checkIns;
    if (leave === undefined) throw new Error('no check-in');
    expect(checkInBlock({ ...leave, restDay: true }, { roster: rosterOf(week) })).toBe(
      '### 11-01 周日 · 队员2 · 计划休息\n- 写的：「下雨」',
    );
  });

  it('keeps only the words of members who agreed to AI use, and the numbering', () => {
    expect(weekText(consentedOnly(week, new Set([leo])))).toBe(
      [
        '# 本周',
        '- 从 2026-10-26（周一）开始',
        '',
        '## 谁是谁（队员N：昵称）',
        '- 队员1',
        '- 队员2',
        '',
        '## 打卡',
        '',
        '### 11-01 周日 · 队员2 · 请假条',
        '- 写的：「下雨」',
      ].join('\n'),
    );
    expect(weekText(consentedOnly(week, new Set([mia])))).toBe(
      [
        '# 本周',
        '- 从 2026-10-26（周一）开始',
        '',
        '## 谁是谁（队员N：昵称）',
        '- 队员1：米亚',
        '- 队员2',
        '',
        '## 打卡',
        '',
        '### 10-27 周二 · 队员1 · 训练：跑步 30 分钟',
        '- 写的：「腿废了」',
      ].join('\n'),
    );
    // Who reacted keeps only members who agreed, too.
    expect(weekText(consentedOnly(week, new Set([mia, leo])))).toContain('点了表情：队员2');
  });

  it('names the squad, and says when a check-in was posted days after the day it counts for', () => {
    const [first] = week.checkIns;
    if (first === undefined) throw new Error('no check-in');
    const backdated = { ...first, comments: [], reactedBy: [], postedDay: '2026-10-29' };
    const roster = rosterOf(week);
    expect(checkInBlock(backdated, { roster })).toBe(
      '### 10-27 周二 · 队员1 · 训练：跑步 30 分钟\n- 补打卡：10-29 周四 才发\n- 写的：「腿废了」',
    );
    // With the author's zone known, the time on their clock too.
    expect(checkInBlock({ ...backdated, postedTime: '23:40' }, { roster })).toContain(
      '\n- 补打卡：10-29 周四 本人当地 23:40 才发\n',
    );
    expect(checkInBlock({ ...first, postedTime: '23:40' }, { roster })).toContain(
      '\n- 本人当地 23:40 发\n',
    );
    expect(weekText({ ...week, name: '周末不睡懒觉', checkIns: [] })).toBe(
      [
        '# 本周',
        '- 队名：周末不睡懒觉',
        '- 从 2026-10-26（周一）开始',
        '',
        '## 谁是谁（队员N：昵称）',
        '- 队员1：米亚',
        '- 队员2',
        '',
        '## 打卡',
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
    const view = { roster, coach: 'xiaohun' };
    expect(shownPaths(view)).toStrictEqual([
      'squad.md',
      'memory.md',
      'me.md',
      'people/队员1.md',
      'people/队员2.md',
    ]);
    expect(storedPathOf('people/队员2.md', view)).toBe(`people/${leo}.md`);
    expect(storedPathOf('memory.md', view)).toBe('memory.md');
    expect(storedPathOf('people/队员3.md', view)).toBeUndefined();
    expect(storedPathOf(`people/${mia}.md`, view)).toBeUndefined();
    expect(storedPathOf('../secrets.md', view)).toBeUndefined();
    expect(shownPathOf(`people/${leo}.md`, view)).toBe('people/队员2.md');
    expect(shownPathOf('people/00000000-0000-4000-8000-000000000000.md', view)).toBeUndefined();
  });

  it('give each coach a page of its own that no other coach reads', () => {
    expect(storedPathOf('me.md', { roster, coach: 'xiaohun' })).toBe('coaches/xiaohun.md');
    expect(storedPathOf('me.md', { roster, coach: 'yalina' })).toBe('coaches/yalina.md');
    expect(storedPathOf('coaches/xiaohun.md', { roster, coach: 'yalina' })).toBeUndefined();
    expect(shownPathOf('coaches/yalina.md', { roster, coach: 'yalina' })).toBe('me.md');
    expect(shownPathOf('coaches/xiaohun.md', { roster, coach: 'yalina' })).toBeUndefined();
    expect(CoachFilePath.safeParse('coaches/yalina.md').success).toBe(true);
    expect(CoachFilePath.safeParse('coaches/../x.md').success).toBe(false);
  });

  it('start a squad’s file from its name, never a copy of who is in it that goes stale', () => {
    expect(squadSeed({ name: '周末不睡懒觉' })).toBe('# 小队\n队名：周末不睡懒觉');
    expect(squadSeed({})).toBe('# 小队');
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

  it('never wakes for a check-in only recorded, not posted', () => {
    const unposted: SquadWeek = {
      ...week,
      checkIns: week.checkIns.map((each) => ({ ...each, unposted: true as const })),
    };
    expect(
      wakesDue({
        squad,
        week: unposted,
        now: new Date('2026-11-01T14:00:00Z'),
        timeZone: 'America/New_York',
      }),
    ).toStrictEqual([
      { squad, reason: { kind: 'dream', day: '2026-11-01' } },
      { squad, reason: { kind: 'daily', day: '2026-11-01' } },
    ]);
  });

  it('wakes for check-ins of the last hour, to dream from 3am and once a day from 6am on the squad’s clock', () => {
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
      { squad, reason: { kind: 'dream', day: '2026-11-01' } },
      { squad, reason: { kind: 'daily', day: '2026-11-01' } },
    ]);
    // 6:00 in Taipei is 17:00 the day before in New York: the squad's own clock.
    expect(
      wakesDue({ squad, week, now: new Date('2026-10-31T22:00:00Z'), timeZone: 'Asia/Taipei' }),
    ).toStrictEqual([
      { squad, reason: { kind: 'dream', day: '2026-11-01' } },
      { squad, reason: { kind: 'daily', day: '2026-11-01' } },
    ]);
    // 5:59 EST: the dream, no daily wake yet.
    expect(
      wakesDue({
        squad,
        week,
        now: new Date('2026-11-01T10:59:00Z'),
        timeZone: 'America/New_York',
      }),
    ).toStrictEqual([{ squad, reason: { kind: 'dream', day: '2026-11-01' } }]);
    // 2:59 EST: nothing yet.
    expect(
      wakesDue({
        squad,
        week,
        now: new Date('2026-11-01T07:59:00Z'),
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
      { squad, reason: { kind: 'dream', day: '2026-11-01' } },
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
    ).toStrictEqual([
      { squad, reason: { kind: 'dream', day: '2026-11-01' } },
      { squad, reason: { kind: 'daily', day: '2026-11-01' } },
    ]);
  });

  it('gives a reply’s wake the whole comment section, every coach named, the reply to answer marked', () => {
    const task = taskOf({
      reason: { kind: 'comment', checkIn: 'c1', comment: 'k2' },
      week,
      files: new Map([['memory.md', undefined]]),
      recentNotes: [],
      thread: {
        now: '10-28 周三 09:30',
        said: [
          { by: { coach: '鸭梨娜' }, text: '第一次跑就跑完了' },
          { by: { member: leo }, text: '强', when: '10-27 周二 20:01' },
          { by: { member: leo }, text: '谢谢', to: { kind: 'reply', coach: '鸭梨娜' } },
          { by: { coach: '鸭梨娜' }, text: '不客气' },
          { by: { member: leo }, text: '教练你也跑吗', to: { kind: 'mention', coach: '你' } },
          { by: 'you', text: '我负责喊' },
          {
            by: { member: mia },
            text: '那你喊大声点',
            to: { kind: 'reply', coach: '你' },
            answering: true,
          },
        ],
      },
    });
    expect(task).toBe(
      [
        // Who wrote the line to answer comes first: here not the post's author.
        '# 队员1回复你',
        '## 这条打卡：10-27 周二 · 队员1 · 训练：跑步 30 分钟\n- 写的：「腿废了」\n- 点了表情：队员2',
        // Everything said under the post, another coach's lines too, so nothing is hidden.
        '## 评论区（先后顺序）\n- 鸭梨娜（教练）：「第一次跑就跑完了」\n- 10-27 周二 20:01 队员2：「强」\n- 队员2（回复鸭梨娜）：「谢谢」\n- 鸭梨娜（教练）：「不客气」\n- 队员2（@你）：「教练你也跑吗」\n- 你：「我负责喊」\n- 队员1（回复你）：「那你喊大声点」（要回的这句）',
        // The time now, so an old @ isn't taken for one just written.
        '## 现在\n10-28 周三 09:30',
        // Who is who, with the nicknames it calls people by, so it never guesses a name.
        '## 谁是谁（队员N：昵称）\n- 队员1：米亚\n- 队员2',
        '## 你的记性（每个文件只列开头几行，其余用 recall 查；查不到的就是不记得）',
        '### memory.md（你和大家之间的事）\n还是空的。',
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
      thread: {
        now: '10-28 周三 09:30',
        said: [{ by: { member: mia }, text: '你看看我吃了啥', answering: true }],
      },
    } as const;
    expect(taskOf(asked)?.split('\n\n')).toContain(
      '## 照片\n这条打卡有 2 张照片，你还没看过。要回的这句问到照片里的东西，就先用 look_at_photos 看。',
    );
    expect(taskOf({ ...asked, week })).not.toContain('look_at_photos');
    // On a holiday the coach is told, after the talk and before its files.
    expect(
      taskOf({
        reason: { kind: 'checkIn', checkIn: 'c1' },
        week,
        files: new Map(),
        recentNotes: [],
        occasions: ['感恩节', 'TURKEY TROT 限时开张'],
      })?.split('\n\n'),
    ).toContain('## 今天\n- 感恩节\n- TURKEY TROT 限时开张');
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

  it('tells a 请假条’s wake the streaks it kept going, as a fact, from two days on', () => {
    const leaveWeek: SquadWeek = {
      ...week,
      checkIns: week.checkIns.map((each) =>
        each.id === 'c1' ? { ...each, kind: 'disclaimer', sport: undefined } : each,
      ),
    };
    const task = (keptStreaks?: { training?: number; meals?: number }) =>
      taskOf({
        reason: { kind: 'checkIn', checkIn: 'c1' },
        week: leaveWeek,
        files: new Map(),
        recentNotes: [],
        ...(keptStreaks === undefined ? {} : { keptStreaks }),
      })?.split('\n\n');
    expect(task({ training: 12, meals: 5 })).toContain(
      '## 连续天数\n请假、休息或放纵餐的那天不断连续，也不算一天。现在连续训练 12 天、连续健康餐 5 天。',
    );
    expect(task({ training: 12, meals: 1 })).toContain(
      '## 连续天数\n请假、休息或放纵餐的那天不断连续，也不算一天。现在连续训练 12 天。',
    );
    expect(task({ training: 1 })?.join('\n\n')).not.toContain('连续天数');
    expect(task()?.join('\n\n')).not.toContain('连续天数');
  });

  it('puts the wakes setting after the soul, its limits filled in, and never the 口头禅', () => {
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
    const instructions = instructionsOf(
      { rules: '规矩', wakes: '回复最多 {replyLimit} 个字，便条最多 {noteLimit} 个字。' },
      coach,
    );
    // The wakes setting comes after the soul, with the API's limits put in.
    expect(instructions).toContain('回复最多 100 个字，便条最多 60 个字。');
    // The 口头禅 is for its card only: told it, the model kept saying it.
    expect(instructions).not.toContain('今天也辛苦啦');
    expect(instructions).not.toContain('口头禅');
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
        '# 新的一天\n2026-11-01，周日。',
        '## 谁是谁（队员N：昵称）\n- 队员1：米亚\n- 队员2',
        '## 和你的对话（过去一天，打卡下面，先后顺序）\n没人在打卡下面和你说话。',
        // What it remembers: each file's beginning, the rest looked up with recall.
        '## 你的记性（每个文件只列开头几行，其余用 recall 查；查不到的就是不记得）',
        '### memory.md（你和大家之间的事）\n```\n米亚爱跑步\n```',
        '### squad.md（这个小队）\n还是空的。',
        // The 战术板 in the squad's language (Simplified Chinese until the week says another),
        // and what it wrote lately.
        '## 战术板\n- 用简体中文写。\n- 你最近写过：\n  - 2026-10-31：周末也要动一动',
        '## 今天的便条\n今天没有要写便条的人。',
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
    ).toStrictEqual(['# 新的一天\n2026-11-26，周四。', '## 今天\n- 感恩节']);
    // A coach hired back is told so, once, after the day's facts; what it says is its own.
    expect(
      taskOf({
        reason: { kind: 'daily', day: '2026-11-26' },
        week,
        files: new Map(),
        recentNotes: [],
        occasions: ['感恩节'],
        backAgain: true,
      })
        ?.split('\n\n')
        .slice(0, 2),
    ).toStrictEqual([
      '# 新的一天\n2026-11-26，周四。',
      '## 今天\n- 感恩节\n- 你以前带过这个小队，被换掉后，现在又被请回来了。',
    ]);
    // A coach that took over is told from whom and when, with the letter it was left, if any.
    expect(
      taskOf({
        reason: { kind: 'daily', day: '2026-11-26' },
        week,
        files: new Map(),
        recentNotes: [],
        handover: { from: '毛头', day: '2026-11-12', letter: '交给你了，大家爱练腿。' },
      })
        ?.split('\n\n')
        .slice(0, 2),
    ).toStrictEqual([
      '# 新的一天\n2026-11-26，周四。',
      '## 你接手这个小队\n2026-11-12 小队换教练，你接替了毛头。\n毛头走时给全队留了一封信，大家都看过：\n「交给你了，大家爱练腿。」',
    ]);
    expect(
      taskOf({
        reason: { kind: 'daily', day: '2026-11-26' },
        week,
        files: new Map(),
        recentNotes: [],
        handover: { from: '毛头', day: '2026-11-12' },
      })
        ?.split('\n\n')
        .at(1),
    ).toBe('## 你接手这个小队\n2026-11-12 小队换教练，你接替了毛头。');
    // Whom it writes a morning note to, by the names it knows them by.
    expect(
      section(
        taskOf({
          reason: { kind: 'daily', day: '2026-11-01' },
          week,
          files: new Map(),
          recentNotes: [],
          noteTo: [
            {
              name: '队员1',
              trainedDays: 2,
              posts: [
                { day: '2026-10-26', what: '游泳 45 分钟' },
                { day: '2026-10-26', what: '健康餐' },
                { day: '2026-10-28', what: '力量' },
              ],
              plan: {
                week: [
                  { kind: 'train', sport: '游泳' },
                  { kind: 'rest' },
                  { kind: 'train', sport: '力量' },
                  { kind: 'rest' },
                  { kind: 'train', sport: '游泳' },
                  { kind: 'train' },
                  { kind: 'rest' },
                ],
                fuelGoals: ['喝够水', '少吃外卖'],
              },
              weather: { words: '今天雨，8–13°C，降水概率 80%；昨天晴，5–12°C', city: '多伦多' },
            },
            {
              name: '队员2',
              trainedDays: 0,
              posts: [],
              plan: {
                week: Array.from({ length: 7 }, () => ({ kind: 'rest' }) as const),
                fuelGoals: [],
              },
            },
            // Plans that couldn't be read: only the days trained.
            { name: '队员3', trainedDays: 1, weather: { words: '今天晴，-2–5°C' } },
          ],
        }),
        '## 今天的便条',
      ),
    ).toBe(
      [
        '## 今天的便条（下面每人各写一张）',
        '### 队员1\n- 本周出赛表：周一游泳，周二休息，周三力量，周四休息，周五游泳，周六练，周日休息\n- 饮食小目标：喝够水、少吃外卖\n- 这周练了：2 天\n- 这周发过：周一游泳 45 分钟、健康餐，周三力量\n- 人在：多伦多\n- 当地天气：今天雨，8–13°C，降水概率 80%；昨天晴，5–12°C',
        '### 队员2\n- 本周出赛表：周一休息，周二休息，周三休息，周四休息，周五休息，周六休息，周日休息\n- 饮食小目标：这周没定\n- 这周练了：0 天\n- 这周发过：还没发过',
        '### 队员3\n- 这周练了：1 天\n- 当地天气：今天晴，-2–5°C',
      ].join('\n\n'),
    );
    // Yesterday's posts, for the notes to pick up on, and a day nobody posted.
    const [posted] = week.checkIns;
    if (posted === undefined) throw new Error('no check-in');
    expect(
      section(
        taskOf({
          reason: { kind: 'daily', day: '2026-10-28' },
          week,
          files: new Map(),
          recentNotes: [],
          yesterday: { day: '2026-10-27', checkIns: [posted] },
        }),
        '## 昨天',
      ),
    ).toBe(
      '## 昨天（周二）小队的动态\n\n### 10-27 周二 · 队员1 · 训练：跑步 30 分钟\n- 写的：「腿废了」\n- 点了表情：队员2\n- 评论（先后顺序）：\n  - 队员2：「强」',
    );
    expect(
      section(
        taskOf({
          reason: { kind: 'daily', day: '2026-10-29' },
          week,
          files: new Map(),
          recentNotes: [],
          yesterday: { day: '2026-10-28', checkIns: [] },
        }),
        '## 昨天',
      ),
    ).toBe('## 昨天（周三）小队的动态\n没人发动态。');
    // The last day's talk under check-ins, for it to remember from.
    const [first] = week.checkIns;
    if (first === undefined) throw new Error('no check-in');
    expect(
      section(
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
        }),
        '## 和你的对话',
      ),
    ).toBe(
      '## 和你的对话（过去一天，打卡下面，先后顺序）\n\n### 10-27 周二 · 队员1 · 训练：跑步 30 分钟\n- 你：「腿废了也算练」\n- 队员2：「我下周膝盖手术」\n- 你：「那这周先歇着」',
    );
    // Yesterday's post points to the talk below only when the talk holds all its comments; the
    // talk keeps only the last day's, so an older comment stays under the post.
    const yesterdayWith = (said: { member: string | undefined; text: string }[]) =>
      section(
        taskOf({
          reason: { kind: 'daily', day: '2026-10-28' },
          week,
          files: new Map(),
          recentNotes: [],
          yesterday: { day: '2026-10-27', checkIns: [first] },
          talks: [{ checkIn: first, said }],
        }),
        '## 昨天',
      );
    expect(yesterdayWith([{ member: leo, text: '强' }])).toContain(
      '\n- 点了表情：队员2\n- 评论：见下面「和你的对话」',
    );
    expect(yesterdayWith([{ member: undefined, text: '谢谢' }])).toContain(
      '\n- 评论（先后顺序）：\n  - 队员2：「强」',
    );
    expect(
      taskOf({
        reason: { kind: 'checkIn', checkIn: 'c2' },
        week,
        files: new Map([['memory.md', undefined]]),
        recentNotes: [],
      }),
    ).toBe(
      [
        '# 有人打卡',
        '## 这条打卡：11-01 周日 · 队员2 · 请假条\n- 写的：「下雨」',
        '## 谁是谁（队员N：昵称）\n- 队员1：米亚\n- 队员2',
        '## 你最近点过的表情\n还没点过。',
        '## 语言\n用简体中文写。',
        '## 你的记性（每个文件只列开头几行，其余用 recall 查；查不到的就是不记得）',
        '### memory.md（你和大家之间的事）\n还是空的。',
      ].join('\n\n'),
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
    ).toContain('\n\n## 你最近点过的表情（新的在前）\n🔥 🔥 💪\n\n');
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
    ).toContain('## 语言\nWrite in English.');
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
    expect(daily).toContain('## 战术板\n- 用繁體中文寫，照台灣的說法。\n- 你还没写过。');
    expect(daily?.slice(-2)).toStrictEqual([
      '### 队员1\n- 这周练了：1 天\n- 用繁體中文寫，照台灣的說法。',
      '### 队员2\n- 这周练了：0 天\n- Write in English.',
    ]);
  });

  it('has nothing to do for a check-in no longer in the week', () => {
    const files = new Map([['memory.md', undefined]]);
    expect(
      taskOf({ reason: { kind: 'checkIn', checkIn: 'gone' }, week, files, recentNotes: [] }),
    ).toBeUndefined();
    expect(
      taskOf({ reason: { kind: 'checkIn', checkIn: 'c2' }, week, files, recentNotes: [] }),
    ).toContain('## 这条打卡：11-01 周日 · 队员2 · 请假条');
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
      checkInBlock(
        { ...first, photos: ['a.jpg', 'b.jpg'], comments: [] },
        { roster: rosterOf(week) },
      ),
    ).toBe(
      '### 10-27 周二 · 队员1 · 训练：跑步 30 分钟\n- 写的：「腿废了」\n- 照片：2 张\n- 点了表情：队员2',
    );
  });
});

describe('a line members read', () => {
  it('never names anyone as 队员N, however the number is written', () => {
    const named = '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。';
    expect(
      ['队员1 加油', '队员 3 加油', '队员３加油'].map((line) => lineProblem(line, 'reply')),
    ).toStrictEqual([named, named, named]);
    expect(lineProblem('全体队员加油', 'reply')).toBeUndefined();
    expect(lineProblem('', 'reply')).toBe('这句是空的。');
  });

  it('holds a Chinese line to the Chinese limit and an English one to the English limit', () => {
    expect(lineProblem('跑'.repeat(100), 'reply')).toBeUndefined();
    expect(lineProblem('跑'.repeat(101), 'reply')).toBe('太长了：101 字，最多 100 字。');
    expect(lineProblem('Run '.repeat(50), 'reply')).toBeUndefined();
    expect(lineProblem('Run '.repeat(50) + '!', 'reply')).toBe(
      '太长了：201 个字符，英文最多 200 个。',
    );
    expect(lineProblem('喝水'.repeat(5), 'challengeTitle')).toBe('太长了：10 字，最多 8 字。');
    expect(lineProblem('Drink water', 'challengeTitle')).toBeUndefined();
  });

  it('reads a line by the letters it is mostly written in, a name in the other aside', () => {
    expect(lineLanguageOf('Hannah 今天跑了五公里，腿还好吗')).toBe('chinese');
    expect(lineLanguageOf('毛头 says hi, nice run today')).toBe('english');
    expect(lineLanguageOf('💪💪')).toBe('chinese');
    expect(longestLine('reply')).toBe(200);
    expect(longestLine('challengeLine')).toBe(48);
  });
});

describe('memory on a waking day', () => {
  it('shows each file’s first lines and how long it is, never the whole file', () => {
    const long = [
      '- 队员1 对花生过敏',
      ...Array.from({ length: 30 }, (_, at) => `- 第 ${String(at)} 件小事，写得长一点占地方`),
    ].join('\n');
    const index = memoryIndex(
      new Map([
        ['people/队员1.md', long],
        ['memory.md', '队员2 想跑半马'],
        ['squad.md', undefined],
      ]),
    );
    const block = index.split('\n\n### memory.md')[0] ?? '';
    // The first fact stays in sight; the rest is only counted.
    expect(block).toContain('- 队员1 对花生过敏');
    expect(block).not.toContain('第 29 件小事');
    expect(block).toContain(`……（共 ${String(long.length)} 字）`);
    const head = block.split('```\n')[1]?.split('\n```')[0] ?? '';
    expect(head.length).toBeLessThanOrEqual(HEAD_LIMIT);
    // A short file shows whole, with no count; an empty one says so.
    expect(index).toContain(
      '### memory.md（你和大家之间的事）\n```\n队员2 想跑半马\n```\n\n### squad.md（这个小队）\n还是空的。',
    );
  });

  it('cuts a first line longer than the head', () => {
    const index = memoryIndex(new Map([['memory.md', '跑'.repeat(HEAD_LIMIT + 50)]]));
    expect(index).toContain(
      `### memory.md（你和大家之间的事）\n\`\`\`\n${'跑'.repeat(HEAD_LIMIT)}\n\`\`\`\n……（共 ${String(HEAD_LIMIT + 50)} 字）`,
    );
  });

  it('the night still reads every file in full', () => {
    const body = Array.from({ length: 40 }, (_, at) => `- 第 ${String(at)} 件事`).join('\n');
    const task = taskOf({
      reason: { kind: 'dream', day: '2026-11-01' },
      week,
      files: new Map([['memory.md', body]]),
      recentNotes: [],
      talks: [],
      pastDays: {
        from: '2026-10-26',
        to: '2026-11-01',
        quiet: false,
        checkIns: week.checkIns,
        boards: [],
        notes: [],
        gifts: [],
      },
    });
    expect(task).toContain('- 第 39 件事');
  });
});

describe('sliceWhole', () => {
  it('cuts before a character it would split in half', () => {
    expect(sliceWhole('跑🏃步', 2)).toBe('跑');
    expect(sliceWhole('跑🏃步', 3)).toBe('跑🏃');
    expect(sliceWhole('跑步', 5)).toBe('跑步');
  });
});

describe('recall', () => {
  const files = new Map([
    ['people/队员1.md', '# 队员1\n- 对花生过敏\n- 想跑半马\n- 周三固定游泳'],
    ['memory.md', '- 队员2 说过讨厌早起\n- 大家约好周日爬山'],
  ]);

  it('finds the lines holding any of the words, in file order, naming each file', () => {
    expect(recallLines(files, { query: '半马 爬山' })).toBe(
      '【people/队员1.md】- 想跑半马\n【memory.md】- 大家约好周日爬山',
    );
  });

  it('finds Chinese worded differently, by most of its two-character pieces', () => {
    // 「游泳时间」 shares 游泳 with 「周三固定游泳」 but not enough of the rest.
    expect(recallLines(files, { query: '周日爬山计划' })).toBe('【memory.md】- 大家约好周日爬山');
    expect(recallLines(files, { query: '花生过敏吗' })).toBe('【people/队员1.md】- 对花生过敏');
    expect(recallLines(files, { query: '爬山周日' })).toBe('【memory.md】- 大家约好周日爬山');
    expect(recallLines(files, { query: '游泳时间' })).toBe(
      '没查到。可以换更短的词，或者不填 query 看整个文件。还是没有，就是不记得，别说你记得。',
    );
  });

  it('lists a whole file top first, leaving out headings', () => {
    expect(recallLines(files, { path: 'people/队员1.md' })).toBe(
      '【people/队员1.md】- 对花生过敏\n【people/队员1.md】- 想跑半马\n【people/队员1.md】- 周三固定游泳',
    );
  });

  it('says plainly when nothing matches, so the coach doesn’t claim to remember', () => {
    expect(recallLines(files, { query: '夸奖' })).toBe(
      '没查到。可以换更短的词，或者不填 query 看整个文件。还是没有，就是不记得，别说你记得。',
    );
    expect(recallLines(new Map([['memory.md', '']]), {})).toBe(
      '没查到，这些文件还是空的。查不到的就是不记得，别说你记得。',
    );
  });

  it('names the files there are when asked for one that isn’t', () => {
    expect(recallLines(files, { path: 'people/队员9.md' })).toBe(
      '没有 people/队员9.md 这个文件；能查的是：people/队员1.md，memory.md。',
    );
  });

  it('stops at its limit and says how many lines are left', () => {
    const many = new Map([
      ['memory.md', Array.from({ length: 300 }, (_, at) => `- 第 ${String(at)} 件事`).join('\n')],
    ]);
    const answer = recallLines(many, {});
    expect(answer.length).toBeLessThanOrEqual(RECALL_LIMIT + 40);
    expect(answer.startsWith('【memory.md】- 第 0 件事')).toBe(true);
    expect(answer).toMatch(/（还有 \d+ 行没列出，换个更具体的词再查）$/);
  });

  it('cuts a line longer than the whole answer instead of leaving it out', () => {
    const answer = recallLines(new Map([['memory.md', '长'.repeat(RECALL_LIMIT * 2)]]), {});
    expect(answer).toBe(
      `${`【memory.md】${'长'.repeat(RECALL_LIMIT * 2)}`.slice(0, RECALL_LIMIT - 1)}…`,
    );
  });
});
