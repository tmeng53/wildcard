import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { MemberId, ModelReply, titlesOf, topCheckInOf, type WeekCheckIn } from './awards.js';
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

  it('refuses no titles, or more than 3', () => {
    const title = { title: '狠人', speech: '周三去跑了。', move: 'pump' as const };
    const many = [1, 2, 3, 4].map((n) => ({ ...title, title: `狠人${String(n)}` }));
    expect(titlesOf({ ...good, awards: [{ member: 'A', titles: [] }] }, [ana])).toBeUndefined();
    expect(titlesOf({ ...good, awards: [{ member: 'A', titles: many }] }, [ana])).toBeUndefined();
    expect(
      titlesOf({ ...good, awards: [{ member: 'A', titles: many.slice(0, 3) }] }, [ana])?.get(ana),
    ).toHaveLength(3);
  });

  it('refuses a title over 6 characters, a line over 24, or either empty', () => {
    const one = (title: string, speech: string) =>
      titlesOf({ ...good, awards: [{ member: 'A', titles: [{ title, speech, move: 'cheer' }] }] }, [
        ana,
      ]);
    expect(one('网球场钉子户', '一'.repeat(24))?.get(ana)?.[0]?.title).toBe('网球场钉子户');
    expect(one('网球场钉子户长', '周三去跑了。')).toBeUndefined();
    expect(one('狠人', '一'.repeat(25))).toBeUndefined();
    expect(one(' ', '周三去跑了。')).toBeUndefined();
  });

  it('refuses a title used twice in the squad', () => {
    const same = { title: '雨中狠人', speech: '周三去跑了。', move: 'pump' as const };
    expect(
      titlesOf(
        {
          ...good,
          awards: [
            { member: 'A', titles: [same] },
            { member: 'B', titles: [same] },
          ],
        },
        [ana, bo],
      ),
    ).toBeUndefined();
  });

  it('refuses body words, ranking words, emoji and line breaks', () => {
    for (const speech of ['这周体重稳住了。', '本周垫底选手。', '周三去跑了🔥', '周三\n去跑了']) {
      expect(
        titlesOf(
          { ...good, awards: [{ member: 'A', titles: [{ title: '狠人', speech, move: 'pump' }] }] },
          [ana],
        ),
      ).toBeUndefined();
    }
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
    const first = checkIn({ id: 'c0000000-0000-4000-8000-000000000001', reactions: { cheer: 2 } });
    const second = checkIn({
      id: 'c0000000-0000-4000-8000-000000000002',
      kind: 'cheatMeal',
      sport: undefined,
      caption: '火锅',
      photos: ['a/b', 'a/c'],
      reactions: { lol: 3 },
    });
    const third = checkIn({
      id: 'c0000000-0000-4000-8000-000000000003',
      reactions: { cheer: 1, lol: 2 },
    });
    expect(topCheckInOf([first, second, third])).toStrictEqual({
      checkIn: third.id,
      day: '2026-10-21',
      kind: 'trained',
      sport: 'run',
      photos: [],
      reactions: { cheer: 1, lol: 2 },
    });
    expect(topCheckInOf([first, second])).toStrictEqual({
      checkIn: second.id,
      day: '2026-10-21',
      kind: 'cheatMeal',
      caption: '火锅',
      photos: ['a/b', 'a/c'],
      reactions: { lol: 3 },
    });
  });

  it('is nothing when no check-in has a reaction', () => {
    expect(topCheckInOf([checkIn({})])).toBeUndefined();
  });
});

const Prompt = z.object({ members: z.unknown(), moves: z.array(z.object({ id: z.string() })) });

describe('promptFor', () => {
  it('lists members by letter with their days, times on their own clock, and the moves, never words about self-harm', () => {
    const prompt = Prompt.parse(
      JSON.parse(
        promptFor({
          weekStart: WeekStart.parse('2026-10-19'),
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
        checkIns: [{ day: '2026-10-21 周三', time: '12:00', kind: '请假条', reason: '（略）' }],
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
    expect(prompt.moves.map(({ id }) => id)).toContain('flat');
    expect(JSON.stringify(prompt)).not.toContain(ana);
  });
});
