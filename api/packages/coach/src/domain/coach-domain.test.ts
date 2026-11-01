import { describe, expect, it } from 'vitest';

import { editBody, FILE_LIMIT, shownBody, shownPaths, storedBody, storedPathOf } from './memory.js';
import { taskOf } from './prompt.js';
import { SquadId } from './settings.js';
import { checkInLine, consentedOnly, rosterOf, weekText, type SquadWeek } from './squad-week.js';
import { costMicros, newYorkTime, wakesDue, weekStartOf, weeksAround } from './wake.js';

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
      comments: [{ member: leo, text: '强' }],
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
      '10-27 周二 队员1 练了 跑步 30 分钟 「腿废了」 · 2 个表情 · 评论：队员2「强」',
    );
    expect(weekText(week)).toBe(
      [
        '本周从 2026-10-26（周一）开始。',
        '队员：队员1（昵称：米亚），队员2',
        '打卡：',
        '- 10-27 周二 队员1 练了 跑步 30 分钟 「腿废了」 · 2 个表情 · 评论：队员2「强」',
        '- 11-01 周日 队员2 请假条 「下雨」',
      ].join('\n'),
    );
    expect(weekText(week)).not.toContain(mia);
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
        '- 10-27 周二 队员1 练了 跑步 30 分钟 「腿废了」 · 2 个表情',
      ].join('\n'),
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
  it('reads New York’s day and hour, and the Monday of a day’s week', () => {
    // 2026-11-01 is the day daylight saving ends; 5:30 UTC is still 1:30 EDT.
    expect(newYorkTime(new Date('2026-11-01T05:30:00Z'))).toStrictEqual({
      day: '2026-11-01',
      hour: 1,
    });
    expect(newYorkTime(new Date('2026-11-01T03:30:00Z'))).toStrictEqual({
      day: '2026-10-31',
      hour: 23,
    });
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

  it('wakes for check-ins of the last hour, and once a day from 6am New York', () => {
    // 10:00 EST: c2 was made 10 minutes ago, c1 days ago.
    expect(wakesDue({ squad, week, now: new Date('2026-11-01T14:00:00Z') })).toStrictEqual([
      { squad, reason: { kind: 'checkIn', checkIn: 'c2' } },
      { squad, reason: { kind: 'daily', day: '2026-11-01' } },
    ]);
    // 5:59 EST: no daily wake yet.
    expect(wakesDue({ squad, week, now: new Date('2026-11-01T10:59:00Z') })).toStrictEqual([]);
  });

  it('counts a wake’s cost at the settings’ prices, rounded up', () => {
    const usage = { requests: 3, inputTokens: 12_000, outputTokens: 800 };
    // $0.25 and $2 per million tokens: 3000 + 1600 millionths.
    expect(
      costMicros(usage, { inputMicrosPerMillion: 250_000, outputMicrosPerMillion: 2_000_000 }),
    ).toBe(4_600);
    expect(
      costMicros(
        { requests: 1, inputTokens: 1, outputTokens: 0 },
        {
          inputMicrosPerMillion: 1,
          outputMicrosPerMillion: 0,
        },
      ),
    ).toBe(1);
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
