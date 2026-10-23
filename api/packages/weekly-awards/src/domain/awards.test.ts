import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { MemberId, ModelReply, titlesOf, topCheckInOf, type WeekCheckIn } from './awards.js';
import { AwardMove } from './moves.js';
import { promptFor } from './prompt.js';
import { WeekStart } from './schedule.js';

const ana = MemberId.parse('a0000000-0000-4000-8000-000000000001');
const bo = MemberId.parse('a0000000-0000-4000-8000-000000000002');

const good: ModelReply = {
  version: 1,
  awards: [
    {
      member: 'A',
      titles: [
        { title: '雨中狠人', speech: '周三下着雨还去跑了 5 公里。', move: 'pump' },
        { title: '早八战神', speech: '连着三天早上七点前打卡。', move: 'warmup' },
      ],
    },
    {
      member: 'B',
      titles: [{ title: '请假条文豪', speech: '周二的请假条写成了连载。', move: 'flat' }],
    },
  ],
};

describe('ModelReply', () => {
  it('tells the model the limits and refuses an answer over them', () => {
    const schema = JSON.stringify(z.toJSONSchema(ModelReply));
    expect(schema).toContain('"maxLength":6');
    expect(schema).toContain('"maxLength":24');
    expect(schema).toContain('"maxItems":3');
    const titled = (title: string, speech = '周三下着雨还去跑了。') => ({
      version: 1,
      awards: [{ member: 'A', titles: [{ title, speech, move: 'pump' }] }],
    });
    expect(ModelReply.safeParse(titled('雨中狠人')).success).toBe(true);
    expect(ModelReply.safeParse(titled('雨中最狠的人啊')).success).toBe(false);
    expect(ModelReply.safeParse(titled('雨中狠人', '周'.repeat(25))).success).toBe(false);
  });
});

describe('titlesOf', () => {
  it('maps each letter back to its member, trimmed', () => {
    const reply: ModelReply = {
      ...good,
      awards: [
        good.awards[1] ?? { member: '', titles: [] },
        {
          member: ' A ',
          titles: [{ title: ' 雨中狠人 ', speech: '周三下着雨还去跑了。 ', move: 'cheer' }],
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
      awards: [{ member: 'A', titles: [{ title, speech, move: 'pump' as const }] }],
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
      titlesOf({ ...good, awards: [{ member: 'A', titles: [title] }] }, [ana])?.get(ana),
    ).toStrictEqual([{ title: '雨中 狠人', speech: '周三下着雨 还去 跑了。', move: 'pump' }]);
  });

  it('leaves the words to the model: the prompt says what they may say', () => {
    const title = { title: '本周第一', speech: '这周练得最多，排第一。', move: 'pump' as const };
    expect(
      titlesOf({ ...good, awards: [{ member: 'A', titles: [title] }] }, [ana])?.get(ana),
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
              checkIns: [checkIn({ kind: 'disclaimer', sport: undefined, text: '最近不想活了' })],
            },
            {
              member: ana,
              timeZone: 'America/Los_Angeles',
              checkIns: [
                checkIn({ caption: '下雨也跑', photos: ['x/y'] }),
                checkIn({
                  kind: 'disclaimer',
                  sport: undefined,
                  text: 'oncall 到半夜',
                  day: '2026-10-22',
                }),
              ],
            },
          ],
        }),
      ),
    );
    expect(prompt.members).toStrictEqual([
      {
        member: 'A',
        checkIns: [
          { day: '2026-10-21 周三', time: '12:00', kind: '请假条', reason: '最近不想活了' },
        ],
      },
      {
        member: 'B',
        checkIns: [
          {
            day: '2026-10-21 周三',
            time: '05:00',
            kind: '练了',
            sport: 'run',
            caption: '下雨也跑',
            photos: 1,
          },
          { day: '2026-10-22 周四', time: '05:00', kind: '请假条', reason: 'oncall 到半夜' },
        ],
      },
    ]);
    expect(prompt.moves).toContainEqual({ id: 'flat', description: 'flat 的样子' });
    expect(prompt.moves).toHaveLength(AwardMove.options.length);
    expect(JSON.stringify(prompt)).not.toContain(ana);
  });
});
