import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  MemberId,
  ModelReply,
  topCheckInOf,
  wordsOf,
  type MemberWeek,
  type SquadPages,
  type WeekCheckIn,
} from './awards.js';
import { AwardMove } from './moves.js';
import { promptFor } from './prompt.js';
import { WeekStart } from './schedule.js';

const ana = MemberId.parse('a0000000-0000-4000-8000-000000000001');
const bo = MemberId.parse('a0000000-0000-4000-8000-000000000002');
const cy = MemberId.parse('a0000000-0000-4000-8000-000000000003');
const NOTE = 'c0000000-0000-4000-8000-0000000000aa';

const none = { line: null, hottest: null };
const noPages = { podium: null, meals: null, bestDisclaimer: null, ending: null };

const good: ModelReply = {
  version: 1,
  order: ['meals', 'myWeek'],
  ...noPages,
  awards: [
    {
      member: 'A',
      titles: [
        { title: '雨中狠人', speech: '周三下着雨还去跑了 5 公里。', move: 'pump' },
        { title: '早八战神', speech: '连着三天早上七点前打卡。', move: 'warmup' },
      ],
      ...none,
    },
    {
      member: 'B',
      titles: [{ title: '请假条文豪', speech: '周二的请假条写成了连载。', move: 'flat' }],
      ...none,
    },
  ],
};

/** The week as the model was asked about it: these members, each with one check-in. */
const weekOf = (members: readonly MemberId[], pages: SquadPages = {}) => ({
  members: members.map((member): MemberWeek => ({
    member,
    timeZone: 'UTC',
    plannedDays: 4,
    trainedDays: 1,
    checkIns: [checkIn({ reactions: { '❤️': 1 } })],
  })),
  pages,
});
const titlesOf = (reply: ModelReply, members: readonly MemberId[]) => {
  const words = wordsOf(reply, weekOf(members));
  return words === undefined
    ? undefined
    : new Map([...words.members].map(([member, { titles }]) => [member, titles]));
};

describe('ModelReply', () => {
  it('tells the model the limits and refuses an answer over them', () => {
    const schema = JSON.stringify(z.toJSONSchema(ModelReply));
    expect(schema).toContain('"maxLength":6');
    expect(schema).toContain('"maxLength":24');
    expect(schema).toContain('"maxItems":3');
    const titled = (title: string, speech = '周三下着雨还去跑了。') => ({
      version: 1,
      order: [],
      ...noPages,
      awards: [{ member: 'A', titles: [{ title, speech, move: 'pump' }], ...none }],
    });
    expect(ModelReply.safeParse(titled('雨中狠人')).success).toBe(true);
    expect(ModelReply.safeParse(titled('雨中最狠的人啊')).success).toBe(false);
    expect(ModelReply.safeParse(titled('雨中狠人', '周'.repeat(25))).success).toBe(false);
  });
});

describe('wordsOf', () => {
  it('maps each letter back to its member, trimmed', () => {
    const reply: ModelReply = {
      ...good,
      awards: [
        good.awards[1] ?? { member: '', titles: [], ...none },
        {
          member: ' A ',
          titles: [{ title: ' 雨中狠人 ', speech: '周三下着雨还去跑了。 ', move: 'cheer' }],
          ...none,
        },
      ],
    };
    expect(titlesOf(reply, [ana, bo])).toStrictEqual(
      new Map([
        [bo, [{ title: '请假条文豪', speech: '周二的请假条写成了连载。', move: 'flat' }]],
        [ana, [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'cheer' }]],
      ]),
    );
  });

  it('refuses a reply with a member missing, repeated or unknown', () => {
    const [first, second] = good.awards;
    if (first === undefined || second === undefined) throw new Error('two awards');
    expect(titlesOf({ ...good, awards: [first] }, [ana, bo])).toBeUndefined();
    expect(titlesOf({ ...good, awards: [first, first] }, [ana, bo])).toBeUndefined();
    expect(
      titlesOf({ ...good, awards: [first, { ...second, member: 'C' }] }, [ana, bo]),
    ).toBeUndefined();
  });

  it('refuses a title or line that is blank once trimmed', () => {
    const blank = (title: string, speech: string) => ({
      ...good,
      awards: [{ member: 'A', titles: [{ title, speech, move: 'pump' as const }], ...none }],
    });
    expect(titlesOf(blank(' ', '周三下着雨还去跑了。'), [ana])).toBeUndefined();
    expect(titlesOf(blank('雨中狠人', '  '), [ana])).toBeUndefined();
  });

  it('keeps a title and line on one line', () => {
    const title = {
      title: '雨中\n狠人',
      speech: '周三下着雨\r\n 还去\u2028跑了。',
      move: 'pump' as const,
    };
    expect(
      titlesOf({ ...good, awards: [{ member: 'A', titles: [title], ...none }] }, [ana])?.get(ana),
    ).toStrictEqual([{ title: '雨中 狠人', speech: '周三下着雨 还去 跑了。', move: 'pump' }]);
  });

  it('keeps the pages’ words only for pages the week has, about members it asked about', () => {
    const reply: ModelReply = {
      version: 1,
      // A page twice, two left out: each once, the missing ones in their usual order.
      order: ['bestDisclaimer', 'meals', 'meals'],
      awards: [
        {
          member: 'A',
          titles: [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'pump' }],
          line: ' 四天全勤 ',
          hottest: { line: '这条火了', move: 'pose' },
        },
      ],
      podium: { speech: '周三下着雨还去跑了 5 公里。', championMove: 'pose', sideMove: 'pump' },
      meals: { line: '火锅两顿' },
      bestDisclaimer: { authorMove: 'flat', squadMove: 'laugh' },
      ending: { headline: '稳了', line: '超额 1 次，多出来那次算利息', move: 'wave' },
    };
    const all = wordsOf(
      reply,
      weekOf([ana], {
        podium: { champion: ana, sides: [] },
        meals: { healthy: 1, cheat: 2 },
        bestDisclaimer: { checkIn: NOTE, author: ana, text: 'oncall' },
        ending: { done: 5, plan: 4 },
      }),
    );
    expect(all?.members.get(ana)).toStrictEqual({
      titles: [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'pump' }],
      line: '四天全勤',
      hottest: { line: '这条火了', move: 'pose' },
    });
    // Each page's words keep the fact they were written for.
    expect(all?.story).toStrictEqual({
      version: 1,
      order: ['bestDisclaimer', 'meals', 'myWeek', 'hottest'],
      podium: {
        champion: ana,
        speech: '周三下着雨还去跑了 5 公里。',
        championMove: 'pose',
        sideMove: 'pump',
      },
      meals: { line: '火锅两顿' },
      bestDisclaimer: { checkIn: NOTE, authorMove: 'flat', squadMove: 'laugh' },
      ending: { hit: true, headline: '稳了', line: '超额 1 次，多出来那次算利息', move: 'wave' },
    });
    // No pages, or a champion and author the model wasn't told about: none of their words.
    expect(wordsOf(reply, weekOf([ana]))?.story).toStrictEqual({
      version: 1,
      order: ['bestDisclaimer', 'meals', 'myWeek', 'hottest'],
    });
    expect(
      wordsOf(
        reply,
        weekOf([ana], {
          podium: { champion: bo, sides: [ana] },
          bestDisclaimer: { checkIn: NOTE, author: bo, text: 'oncall' },
        }),
      )?.story,
    ).toStrictEqual({ version: 1, order: ['bestDisclaimer', 'meals', 'myWeek', 'hottest'] });
  });

  it('leaves the words to the model: the prompt says what they may say', () => {
    const title = { title: '本周第一', speech: '这周练得最多，排第一。', move: 'pump' as const };
    expect(
      titlesOf({ ...good, awards: [{ member: 'A', titles: [title], ...none }] }, [ana])?.get(ana),
    ).toStrictEqual([title]);
  });
});

const checkIn = (overrides: Partial<WeekCheckIn>): WeekCheckIn => ({
  id: 'c0000000-0000-4000-8000-000000000001',
  day: '2026-10-21',
  createdAt: new Date('2026-10-21T12:00:00.000Z'),
  kind: 'trained',
  sport: 'run',
  photos: [],
  reactions: {},
  ...overrides,
});

describe('topCheckInOf', () => {
  it('is the check-in with the most reactions, the latest on a tie', () => {
    const first = checkIn({ id: 'c0000000-0000-4000-8000-000000000001', reactions: { '❤️': 2 } });
    const second = checkIn({
      id: 'c0000000-0000-4000-8000-000000000002',
      kind: 'cheatMeal',
      sport: undefined,
      caption: '火锅',
      photos: ['a/b', 'a/c'],
      reactions: { '😂': 3 },
    });
    const third = checkIn({
      id: 'c0000000-0000-4000-8000-000000000003',
      reactions: { '❤️': 1, '😂': 2 },
    });
    expect(topCheckInOf([first, second, third])).toStrictEqual({
      checkIn: third.id,
      day: '2026-10-21',
      kind: 'trained',
      sport: 'run',
      photos: [],
      reactions: { '❤️': 1, '😂': 2 },
    });
    expect(topCheckInOf([first, second])).toStrictEqual({
      checkIn: second.id,
      day: '2026-10-21',
      kind: 'cheatMeal',
      caption: '火锅',
      photos: ['a/b', 'a/c'],
      reactions: { '😂': 3 },
    });
  });

  it('is nothing when no check-in has a reaction', () => {
    expect(topCheckInOf([checkIn({})])).toBeUndefined();
  });
});

const Prompt = z.object({
  members: z.unknown(),
  pages: z.unknown(),
  moves: z.array(z.object({ id: z.string(), description: z.string() })),
});

const moves = z
  .record(AwardMove, z.string())
  .parse(Object.fromEntries(AwardMove.options.map((move) => [move, `${move} 的样子`])));

describe('promptFor', () => {
  it('lists members by letter with their days, times on their own clock, and the moves', () => {
    const prompt = Prompt.parse(
      JSON.parse(
        promptFor({
          weekStart: WeekStart.parse('2026-10-19'),
          moves,
          members: [
            {
              member: bo,
              timeZone: 'UTC',
              plannedDays: 3,
              trainedDays: 0,
              checkIns: [checkIn({ kind: 'disclaimer', sport: undefined, text: '最近不想活了' })],
            },
            {
              member: ana,
              timeZone: 'America/Los_Angeles',
              plannedDays: 4,
              trainedDays: 1,
              checkIns: [
                checkIn({ caption: '下雨也跑', photos: ['x/y'], reactions: { '😂': 1 } }),
                checkIn({
                  id: 'c0000000-0000-4000-8000-000000000002',
                  kind: 'disclaimer',
                  sport: undefined,
                  text: 'oncall 到半夜',
                  day: '2026-10-22',
                }),
              ],
            },
          ],
          pages: {
            podium: { champion: ana, sides: [cy, bo] },
            meals: { healthy: 2, cheat: 1 },
            bestDisclaimer: { checkIn: NOTE, author: cy, text: '别人的请假条' },
            ending: { done: 1, plan: 7 },
          },
        }),
      ),
    );
    expect(prompt.pages).toStrictEqual({
      podium: { champion: 'B', sides: ['A'] },
      meals: { healthy: 2, cheat: 1 },
      ending: { done: 1, plan: 7, hit: false },
    });
    expect(prompt.members).toStrictEqual([
      {
        member: 'A',
        plannedDays: 3,
        trainedDays: 0,
        checkIns: [
          { day: '2026-10-21 周三', time: '12:00', kind: '请假条', reason: '最近不想活了' },
        ],
      },
      {
        member: 'B',
        plannedDays: 4,
        trainedDays: 1,
        checkIns: [
          {
            day: '2026-10-21 周三',
            time: '05:00',
            kind: '练了',
            sport: 'run',
            caption: '下雨也跑',
            photos: 1,
            hottest: true,
          },
          { day: '2026-10-22 周四', time: '05:00', kind: '请假条', reason: 'oncall 到半夜' },
        ],
      },
    ]);
    expect(prompt.moves).toContainEqual({ id: 'flat', description: 'flat 的样子' });
    expect(prompt.moves).toHaveLength(AwardMove.options.length);
    expect(JSON.stringify(prompt)).not.toContain(ana);
    // Nothing of a member who isn't listed: not their 请假条, not their place on the podium.
    expect(JSON.stringify(prompt)).not.toContain('别人的请假条');
  });

  it('lists the moves in their own order, whatever order the settings keep them in', () => {
    const reversed = z
      .record(AwardMove, z.string())
      .parse(Object.fromEntries(Object.entries(moves).reverse()));
    const prompt = Prompt.parse(
      JSON.parse(
        promptFor({
          weekStart: WeekStart.parse('2026-10-19'),
          moves: reversed,
          members: [],
          pages: {},
        }),
      ),
    );
    expect(prompt.moves.map(({ id }) => id)).toStrictEqual([
      'cheer',
      'pump',
      'pose',
      'warmup',
      'stretch',
      'doze',
      'flat',
      'laugh',
      'wave',
      'fullbelly',
    ]);
  });
});
