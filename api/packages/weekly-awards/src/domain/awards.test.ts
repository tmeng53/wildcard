import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  boardOf,
  MemberId,
  modelReplyFor,
  SquadId,
  titlesOf,
  titlesWonOf,
  topCheckInOf,
  wornOf,
  type ModelReply,
  type TitleWin,
  type WeekCheckIn,
} from './awards.js';
import { BadgeCatalog, DEFAULT_BADGE } from './badges.js';
import { AwardMove } from './moves.js';
import { PROMPT_COMMENTS, promptFor } from './prompt.js';
import { WeekStart } from './schedule.js';

const catalog = BadgeCatalog.parse({
  shapes: [
    { id: 'shield', meaning: '盾牌' },
    { id: 'circle', meaning: '圆' },
  ],
  colours: [{ id: 'track', meaning: '红' }],
  glyphs: [
    { id: 'sun.max.fill', meaning: '太阳' },
    { id: 'moon.fill', meaning: '月亮' },
  ],
});
const ModelReply = modelReplyFor(catalog);
const badge = { shape: 'shield', colour: 'track', glyph: 'sun.max.fill' } as const;

const ana = MemberId.parse('a0000000-0000-4000-8000-000000000001');
const bo = MemberId.parse('a0000000-0000-4000-8000-000000000002');

const good: ModelReply = {
  version: 1,
  awards: [
    {
      member: 'A',
      titles: [
        { title: '雨中狠人', speech: '周三下着雨还去跑了 5 公里。', move: 'pump', badge },
        { title: '早八战神', speech: '连着三天早上七点前打卡。', move: 'warmup', badge },
      ],
    },
    {
      member: 'B',
      titles: [{ title: '请假条文豪', speech: '周二的请假条写成了连载。', move: 'flat', badge }],
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
      awards: [{ member: 'A', titles: [{ title, speech, move: 'pump', badge }] }],
    });
    expect(ModelReply.safeParse(titled('雨中狠人')).success).toBe(true);
    expect(ModelReply.safeParse(titled('雨中最狠的人啊')).success).toBe(false);
    expect(ModelReply.safeParse(titled('雨中狠人', '周'.repeat(25))).success).toBe(false);
  });

  it('takes badges only from the catalog', () => {
    const titled = (picked: Record<string, string>) => ({
      version: 1,
      awards: [
        {
          member: 'A',
          titles: [{ title: '夜跑王', speech: '周三半夜还在跑。', move: 'pump', badge: picked }],
        },
      ],
    });
    expect(ModelReply.safeParse(titled({ ...badge, glyph: 'moon.fill' })).success).toBe(true);
    expect(ModelReply.safeParse(titled({ ...badge, glyph: 'flame.fill' })).success).toBe(false);
    expect(ModelReply.safeParse(titled({ ...badge, shape: 'hexagon' })).success).toBe(false);
    expect(ModelReply.safeParse(titled({ ...badge, colour: 'pool' })).success).toBe(false);
    const schema = JSON.stringify(z.toJSONSchema(ModelReply));
    expect(schema).toContain('"enum":["sun.max.fill","moon.fill"]');
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
          titles: [{ title: ' 雨中狠人 ', speech: '周三下着雨还去跑了。 ', move: 'cheer', badge }],
        },
      ],
    };
    expect(titlesOf(reply, [ana, bo])).toStrictEqual(
      new Map([
        [bo, [{ title: '请假条文豪', speech: '周二的请假条写成了连载。', move: 'flat', badge }]],
        [ana, [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'cheer', badge }]],
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
      awards: [{ member: 'A', titles: [{ title, speech, move: 'pump' as const, badge }] }],
    });
    expect(titlesOf(blank(' ', '周三下着雨还去跑了。'), [ana])).toBeUndefined();
    expect(titlesOf(blank('雨中狠人', '  '), [ana])).toBeUndefined();
  });

  it('keeps a title and line on one line', () => {
    const title = {
      title: '雨中\n狠人',
      speech: '周三下着雨\r\n 还去\u2028跑了。',
      move: 'pump' as const,
      badge,
    };
    expect(
      titlesOf({ ...good, awards: [{ member: 'A', titles: [title] }] }, [ana])?.get(ana),
    ).toStrictEqual([
      { title: '雨中 狠人', speech: '周三下着雨 还去 跑了。', move: 'pump', badge },
    ]);
  });

  it('leaves the words to the model: the prompt says what they may say', () => {
    const title = {
      title: '本周第一',
      speech: '这周练得最多，排第一。',
      move: 'pump' as const,
      badge,
    };
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
  memes: z.array(z.unknown()).optional(),
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
          badges: catalog,
          memes: [],
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
    expect(prompt.memes).toBeUndefined();
  });

  it('brings the memes in use, with what each means', () => {
    const prompt = Prompt.parse(
      JSON.parse(
        promptFor({
          weekStart: WeekStart.parse('2026-10-19'),
          moves,
          badges: catalog,
          members: [],
          memes: [{ phrase: '对自己很好', meaning: '照顾好自己', background: '小红书上流行' }],
        }),
      ),
    );
    expect(prompt.memes).toStrictEqual([
      { phrase: '对自己很好', meaning: '照顾好自己', background: '小红书上流行' },
    ]);
  });

  it('gives each check-in its comments, writers by letter or as 队友 when they aren’t listed', () => {
    const cy = MemberId.parse('a0000000-0000-4000-8000-000000000003');
    const prompt = Prompt.parse(
      JSON.parse(
        promptFor({
          weekStart: WeekStart.parse('2026-10-19'),
          moves,
          badges: catalog,
          memes: [],
          members: [
            {
              member: ana,
              timeZone: 'UTC',
              checkIns: [
                checkIn({
                  comments: [
                    { member: bo, text: '腿还在吗' },
                    { member: ana, text: '不在了', replyTo: bo },
                    { member: cy, text: '下周带我', replyTo: ana },
                  ],
                }),
              ],
            },
            { member: bo, timeZone: 'UTC', checkIns: [checkIn({ comments: [] })] },
          ],
        }),
      ),
    );
    expect(prompt.members).toStrictEqual([
      {
        member: 'A',
        checkIns: [
          {
            day: '2026-10-21 周三',
            time: '12:00',
            kind: '练了',
            sport: 'run',
            comments: [
              { from: 'B', text: '腿还在吗' },
              { from: 'A', to: 'B', text: '不在了' },
              { from: '队友', to: 'A', text: '下周带我' },
            ],
          },
        ],
      },
      {
        member: 'B',
        checkIns: [{ day: '2026-10-21 周三', time: '12:00', kind: '练了', sport: 'run' }],
      },
    ]);
    expect(JSON.stringify(prompt)).not.toContain(cy);
  });

  it('brings only a check-in’s latest comments, so a busy post can’t swell the call', () => {
    const many = Array.from({ length: PROMPT_COMMENTS + 5 }, (_, index) => ({
      member: bo,
      text: `第${String(index)}条`,
    }));
    const prompt = Prompt.parse(
      JSON.parse(
        promptFor({
          weekStart: WeekStart.parse('2026-10-19'),
          moves,
          badges: catalog,
          memes: [],
          members: [{ member: ana, timeZone: 'UTC', checkIns: [checkIn({ comments: many })] }],
        }),
      ),
    );
    const [only] = z
      .array(z.object({ checkIns: z.array(z.object({ comments: z.array(z.unknown()) })) }))
      .parse(prompt.members);
    const comments = only?.checkIns[0]?.comments ?? [];
    expect(comments).toHaveLength(PROMPT_COMMENTS);
    expect(comments[0]).toStrictEqual({ from: '队友', text: '第5条' });
    expect(comments.at(-1)).toStrictEqual({
      from: '队友',
      text: `第${String(PROMPT_COMMENTS + 4)}条`,
    });
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
          badges: catalog,
          members: [],
          memes: [],
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

const squad = SquadId.parse('b0000000-0000-4000-8000-000000000001');
const other = SquadId.parse('b0000000-0000-4000-8000-000000000002');

/** Wins in the order the store gives them: the latest week first. */
const win = (
  [weekStart, title]: readonly [string, string],
  overrides: Partial<TitleWin> = {},
): TitleWin => ({
  squad,
  weekStart: WeekStart.parse(weekStart),
  title: { title, speech: `${weekStart} 的颁奖词`, move: 'pump', badge },
  ...overrides,
});

describe('boardOf', () => {
  it('lists each title once, the latest won first, with every week it was won', () => {
    const moon = { ...badge, glyph: 'moon.fill' };
    const wins = [
      win(['2026-10-26', '早八战神'], {
        title: { title: '早八战神', speech: '最新', move: 'pump', badge: moon },
      }),
      win(['2026-10-26', '雨中狠人']),
      win(['2026-10-19', '夜跑王'], { squad: other }),
      win(['2026-10-12', '早八战神']),
    ];
    expect(boardOf(wins)).toStrictEqual([
      {
        title: '早八战神',
        badge: moon,
        weeks: [
          { squad, weekStart: '2026-10-26', speech: '最新' },
          { squad, weekStart: '2026-10-12', speech: '2026-10-12 的颁奖词' },
        ],
      },
      {
        title: '雨中狠人',
        badge,
        weeks: [{ squad, weekStart: '2026-10-26', speech: '2026-10-26 的颁奖词' }],
      },
      {
        title: '夜跑王',
        badge,
        weeks: [{ squad: other, weekStart: '2026-10-19', speech: '2026-10-19 的颁奖词' }],
      },
    ]);
  });

  it('gives titles won before badges the default one', () => {
    const plain = win(['2026-10-12', '早八战神'], {
      title: { title: '早八战神', speech: '早', move: 'pump' },
    });
    expect(boardOf([plain])[0]?.badge).toStrictEqual(DEFAULT_BADGE);
  });
});

describe('wornOf', () => {
  const board = boardOf([win(['2026-10-26', '早八战神']), win(['2026-10-19', '夜跑王'])]);

  it('wears the title equipped, else the latest won', () => {
    expect(wornOf(board, '夜跑王')?.title).toBe('夜跑王');
    expect(wornOf(board, null)?.title).toBe('早八战神');
  });

  it('falls back to the latest when the equipped title is no longer on the board', () => {
    expect(wornOf(board, '雨中狠人')?.title).toBe('早八战神');
    expect(wornOf([], '雨中狠人')).toBeUndefined();
  });
});

describe('titlesWonOf', () => {
  it('counts every title won, and how often the latest was won', () => {
    expect(
      titlesWonOf(
        boardOf([
          win(['2026-10-26', '早八战神']),
          win(['2026-10-26', '雨中狠人']),
          win(['2026-10-19', '早八战神']),
          win(['2026-10-12', '夜跑王']),
        ]),
      ),
    ).toStrictEqual({ count: 4, latest: { title: '早八战神', times: 2 } });
  });

  it('has no latest before the first award', () => {
    expect(titlesWonOf([])).toStrictEqual({ count: 0 });
  });
});
