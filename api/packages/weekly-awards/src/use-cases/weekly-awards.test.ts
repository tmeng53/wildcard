import { randomUUID } from 'node:crypto';

import { isAppError } from '@wildcard/errors';
import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresAwardsStore,
  type WeeklyAwardTables,
} from '../adapters/postgres-awards-store.js';
import {
  MemberId,
  SquadId,
  type MemberWeek,
  type ModelReply,
  type SquadPages,
} from '../domain/awards.js';
import { WeekStart } from '../domain/schedule.js';
import { AwardsModelMissingError, AwardsWriterUnavailableError } from '../errors.js';
import type { LanguageModel } from '../ports.js';
import { createWeeklyAwards } from './weekly-awards.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database. The
// model is the port's: it answers what each test sets and counts how often it was asked.
const db = new Kysely<WeeklyAwardTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

const week = WeekStart.parse('2026-10-19');

const reply: ModelReply = {
  version: 1,
  order: ['meals', 'hottest', 'myWeek', 'bestDisclaimer'],
  awards: [
    {
      member: 'A',
      titles: [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'pump' }],
      line: '雨天也出勤',
      hottest: { line: '这条点赞两个', move: 'pose' },
    },
    {
      member: 'B',
      titles: [{ title: '请假条文豪', speech: '周四的请假条写成了连载。', move: 'flat' }],
      line: null,
      // B has no check-in with a reaction: this one is dropped.
      hottest: { line: '没人点赞', move: 'pose' },
    },
  ],
  podium: { speech: '周三下着雨还去跑了 5 公里。', championMove: 'pose', sideMove: 'pump' },
  meals: null,
  bestDisclaimer: null,
  ending: { headline: '差一点', line: '还差 3 天，腿已经在热身了', move: 'warmup' },
};

/** The squad's pages, none unless a test sets them. */
const pages: SquadPages = {};

function setup(
  answers: (() => Promise<unknown>)[] = [() => Promise.resolve(reply)],
  agreed: (member: MemberId) => boolean = () => true,
) {
  const asked: string[] = [];
  const model: LanguageModel = {
    answer: async ({ prompt, reply: shape }) => {
      const next = answers[Math.min(asked.length, answers.length - 1)];
      asked.push(prompt);
      if (next === undefined) throw new Error('no answer set');
      return shape.parse(await next());
    },
  };
  const consentAsked: (readonly MemberId[])[] = [];
  const awards = createWeeklyAwards({
    model,
    store: createPostgresAwardsStore(db),
    aiConsented: (members) => {
      consentAsked.push(members);
      return Promise.resolve(members.filter(agreed));
    },
  });
  return { awards, asked, consentAsked };
}

async function newSquad() {
  const id = SquadId.parse(randomUUID());
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${id})`.execute(
    db,
  );
  return id;
}

/** A member with an account, as winners must have. */
async function member() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id, email) values (${id}, ${`${id}@example.com`})`.execute(db);
  return id;
}

const checkIn = (reactions: Record<string, number> = {}) => ({
  id: randomUUID(),
  day: '2026-10-21',
  createdAt: new Date('2026-10-21T12:00:00.000Z'),
  kind: 'trained' as const,
  sport: 'run',
  photos: [],
  reactions,
});

const weekOf = ([ana, bo, cy]: readonly [MemberId, MemberId, MemberId]): MemberWeek[] => [
  {
    member: ana,
    timeZone: 'UTC',
    plannedDays: 2,
    trainedDays: 2,
    checkIns: [checkIn({ '❤️': 2 }), checkIn()],
  },
  { member: cy, timeZone: 'UTC', plannedDays: 3, trainedDays: 0, checkIns: [] },
  { member: bo, timeZone: 'UTC', plannedDays: 3, trainedDays: 1, checkIns: [checkIn()] },
];

async function reasonOf(promise: Promise<unknown>) {
  try {
    await promise;
    return 'ok';
  } catch (error) {
    return isAppError(error) ? error.reason : error;
  }
}

describe('createWeeklyAwards', () => {
  it('gives titles to members who checked in, nothing to anyone who didn’t, once', async () => {
    const { awards, asked } = setup();
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const members = weekOf([ana, bo, cy]);
    // Ana on the podium, the squad short of its plan.
    const given = await awards.give({
      squad,
      weekStart: week,
      members,
      pages: { podium: { champion: ana, sides: [] }, ending: { done: 3, plan: 8 } },
    });
    expect(given).toStrictEqual({
      members: [
        {
          member: ana,
          titles: [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'pump' }],
          line: '雨天也出勤',
          hottest: { line: '这条点赞两个', move: 'pose' },
          topCheckIn: {
            checkIn: members[0]?.checkIns[0]?.id,
            day: '2026-10-21',
            kind: 'trained',
            sport: 'run',
            photos: [],
            reactions: { '❤️': 2 },
          },
        },
        {
          member: bo,
          titles: [{ title: '请假条文豪', speech: '周四的请假条写成了连载。', move: 'flat' }],
        },
      ],
      story: {
        version: 1,
        order: ['meals', 'hottest', 'myWeek', 'bestDisclaimer'],
        podium: {
          champion: ana,
          speech: '周三下着雨还去跑了 5 公里。',
          championMove: 'pose',
          sideMove: 'pump',
        },
        ending: {
          hit: false,
          headline: '差一点',
          line: '还差 3 天，腿已经在热身了',
          move: 'warmup',
        },
      },
    });
    expect(asked).toHaveLength(1);
    expect(asked[0]).not.toContain(cy);
    expect(asked[0]).toContain('"podium":{"champion":"A","sides":[]}');
    // Asked again, the same awards, without asking the model.
    expect(await awards.give({ squad, weekStart: week, members, pages })).toStrictEqual(given);
    expect(await awards.find({ squad, weekStart: week })).toStrictEqual({
      status: 'given',
      awards: given,
    });
    expect(asked).toHaveLength(1);
  });

  it('sends the model only the weeks of members who agreed to AI use, and awards only them', async () => {
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const { awards, asked, consentAsked } = setup(
      [() => Promise.resolve({ ...reply, awards: reply.awards.slice(0, 1) })],
      (each) => each === ana,
    );
    const given = await awards.give({
      squad,
      weekStart: week,
      members: weekOf([ana, bo, cy]),
      pages,
    });
    expect(consentAsked).toStrictEqual([[ana, bo]]);
    expect(given.members.map(({ member: each }) => each)).toStrictEqual([ana]);
    expect(asked).toHaveLength(1);
    expect(asked[0]).toContain('"member":"A"');
    expect(asked[0]).not.toContain('"member":"B"');
  });

  it('asks the model nothing when nobody who checked in agreed to AI use', async () => {
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const { awards, asked } = setup(undefined, () => false);
    expect(
      await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]), pages }),
    ).toStrictEqual({
      members: [],
      story: { version: 1, order: ['myWeek', 'hottest', 'meals', 'bestDisclaimer'] },
    });
    expect(asked).toHaveLength(0);
  });

  it('asks once more when the first answer fails the checks', async () => {
    const bad = { ...reply, awards: reply.awards.slice(0, 1) };
    const { awards, asked } = setup([() => Promise.resolve(bad), () => Promise.resolve(reply)]);
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    expect(
      await reasonOf(
        awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]), pages }),
      ),
    ).toBe('ok');
    expect(asked).toHaveLength(2);
  });

  it('saves only the failed try and why when no answer passes, so the next run tries again', async () => {
    const down = setup([() => Promise.reject(new Error('down'))]);
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const members = weekOf([ana, bo, cy]);
    expect(await reasonOf(down.awards.give({ squad, weekStart: week, members, pages }))).toBe(
      'AWARDS_WRITER_UNAVAILABLE',
    );
    expect(down.asked).toHaveLength(2);
    expect(await down.awards.find({ squad, weekStart: week })).toStrictEqual({
      status: 'failing',
      failures: { count: 1, lastError: 'Error' },
    });
    expect(await down.awards.claimWinners({ squad, weekStart: week })).toStrictEqual([]);
    const { awards } = setup();
    expect((await awards.give({ squad, weekStart: week, members, pages })).members).toHaveLength(2);
  });

  it('gives a squad where nobody checked in no awards, without asking the model', async () => {
    const { awards, asked } = setup();
    const squad = await newSquad();
    const members = [
      { member: await member(), timeZone: 'UTC', plannedDays: 5, trainedDays: 0, checkIns: [] },
    ];
    expect(await awards.give({ squad, weekStart: week, members, pages })).toStrictEqual({
      members: [],
      story: { version: 1, order: ['myWeek', 'hottest', 'meals', 'bestDisclaimer'] },
    });
    expect(asked).toStrictEqual([]);
    expect(await awards.claimWinners({ squad, weekStart: week })).toStrictEqual([]);
  });

  it('keeps one set of awards when two runs write at once', async () => {
    const other = {
      ...reply,
      awards: reply.awards.map((award) => ({
        ...award,
        titles: award.titles.map((title) => ({ ...title, title: `${title.title.slice(0, 4)}二` })),
      })),
    };
    const first = setup();
    const second = setup([() => Promise.resolve(other)]);
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const members = weekOf([ana, bo, cy]);
    const [a, b] = await Promise.all([
      first.awards.give({ squad, weekStart: week, members, pages }),
      second.awards.give({ squad, weekStart: week, members, pages }),
    ]);
    expect(a).toStrictEqual(b);
    expect(await first.awards.find({ squad, weekStart: week })).toStrictEqual({
      status: 'given',
      awards: a,
    });
  });

  it('hands out the winners to tell once', async () => {
    const { awards } = setup();
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    expect(await awards.claimWinners({ squad, weekStart: week })).toStrictEqual([]);
    await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]), pages });
    const claims = await Promise.all(
      [1, 2, 3].map(() => awards.claimWinners({ squad, weekStart: week })),
    );
    expect(claims.filter((claim) => claim.length > 0)).toStrictEqual([[ana, bo]]);
  });

  it('drops a deleted account’s awards everywhere, and only theirs', async () => {
    const { awards } = setup();
    const [ana, bo, cy] = [await member(), await member(), await member()];
    const squads = [await newSquad(), await newSquad()];
    for (const squad of squads) {
      await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]), pages });
    }
    await sql`delete from auth.users where id = ${ana}`.execute(db);
    for (const squad of squads) {
      const kept = await awards.find({ squad, weekStart: week });
      expect(
        kept?.status === 'given' ? kept.awards.members.map((each) => each.member) : kept,
      ).toStrictEqual([bo]);
    }
  });

  it('saves nothing for a week read before a winner’s account was deleted, so the next run reads it again', async () => {
    const { awards } = setup();
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const members = weekOf([ana, bo, cy]);
    await sql`delete from auth.users where id = ${bo}`.execute(db);
    await expect(awards.give({ squad, weekStart: week, members, pages })).rejects.toThrow();
    expect(await awards.find({ squad, weekStart: week })).toBeUndefined();
    const fresh = members.filter(({ member: each }) => each !== bo);
    const alone = setup([() => Promise.resolve({ ...reply, awards: reply.awards.slice(0, 1) })]);
    const given = await alone.awards.give({ squad, weekStart: week, members: fresh, pages });
    expect(given.members.map((each) => each.member)).toStrictEqual([ana]);
  });

  it('keeps a missing model key by name, so the admins know to set it', async () => {
    const off = setup([
      () =>
        Promise.reject(new AwardsWriterUnavailableError({ cause: new AwardsModelMissingError() })),
    ]);
    const squad = await newSquad();
    const members = weekOf([await member(), await member(), await member()]);
    await reasonOf(off.awards.give({ squad, weekStart: week, members, pages }));
    expect(await off.awards.claimNudge({ squad, weekStart: week })).toStrictEqual({
      count: 1,
      lastError: 'AwardsModelMissingError',
    });
  });

  it('hands out a nudge once per failed try, and once before the first, never once given', async () => {
    const quota = Object.assign(new Error('429 You exceeded your current quota: 我的请假条'), {
      name: 'RateLimitError',
      status: 429,
      code: 'insufficient_quota',
    });
    const down = setup([() => Promise.reject(new Error('unavailable', { cause: quota }))]);
    const [squad, given] = [await newSquad(), await newSquad()];
    const members = weekOf([await member(), await member(), await member()]);
    const nudge = () => down.awards.claimNudge({ squad, weekStart: week });
    expect(await nudge()).toStrictEqual({ count: 0 });
    expect(await nudge()).toBeUndefined();

    await reasonOf(down.awards.give({ squad, weekStart: week, members, pages }));
    const nudges = await Promise.all([nudge(), nudge(), nudge()]);
    // The provider's name, status and code, never its message.
    const lastError = 'RateLimitError 429 insufficient_quota';
    expect(nudges.filter((each) => each !== undefined)).toStrictEqual([{ count: 1, lastError }]);
    await reasonOf(down.awards.give({ squad, weekStart: week, members, pages }));
    expect(await nudge()).toStrictEqual({ count: 2, lastError });
    expect(await nudge()).toBeUndefined();

    const { awards } = setup();
    await awards.give({ squad: given, weekStart: week, members, pages });
    expect(await awards.claimNudge({ squad: given, weekStart: week })).toBeUndefined();
    // A nudged week still takes its awards when a try passes, and isn't nudged after.
    await awards.give({ squad, weekStart: week, members, pages });
    expect((await awards.find({ squad, weekStart: week }))?.status).toBe('given');
    expect(await nudge()).toBeUndefined();
  });

  it('keeps an answer that failed the checks as FailedChecks, even after an error', async () => {
    const bad = { ...reply, awards: reply.awards.slice(0, 1) };
    const { awards } = setup([
      () => Promise.reject(Object.assign(new Error('timed out'), { name: 'Timeout' })),
      () => Promise.resolve(bad),
    ]);
    const squad = await newSquad();
    const members = weekOf([await member(), await member(), await member()]);
    await reasonOf(awards.give({ squad, weekStart: week, members, pages }));
    expect(await awards.find({ squad, weekStart: week })).toStrictEqual({
      status: 'failing',
      failures: { count: 1, lastError: 'FailedChecks' },
    });
  });
});
