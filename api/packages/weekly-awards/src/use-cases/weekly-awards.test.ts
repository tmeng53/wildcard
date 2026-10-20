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
import { MemberId, SquadId, type MemberWeek, type ModelReply } from '../domain/awards.js';
import { WeekStart } from '../domain/schedule.js';
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
  awards: [
    { member: 'A', titles: [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'pump' }] },
    {
      member: 'B',
      titles: [{ title: '请假条文豪', speech: '周四的请假条写成了连载。', move: 'flat' }],
    },
  ],
};

function setup(answers: (() => Promise<unknown>)[] = [() => Promise.resolve(reply)]) {
  const asked: string[] = [];
  const model: LanguageModel = {
    answer: async ({ prompt, reply: shape }) => {
      const next = answers[Math.min(asked.length, answers.length - 1)];
      asked.push(prompt);
      if (next === undefined) throw new Error('no answer set');
      return shape.parse(await next());
    },
  };
  return { awards: createWeeklyAwards({ model, store: createPostgresAwardsStore(db) }), asked };
}

async function newSquad() {
  const id = SquadId.parse(randomUUID());
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${id})`.execute(
    db,
  );
  return id;
}

const member = () => MemberId.parse(randomUUID());

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
  { member: ana, timeZone: 'UTC', checkIns: [checkIn({ cheer: 2 }), checkIn()] },
  { member: cy, timeZone: 'UTC', checkIns: [] },
  { member: bo, timeZone: 'UTC', checkIns: [checkIn()] },
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
    const [squad, ana, bo, cy] = [await newSquad(), member(), member(), member()];
    const members = weekOf([ana, bo, cy]);
    const given = await awards.give({ squad, weekStart: week, members });
    expect(given).toStrictEqual({
      version: 1,
      members: [
        {
          member: ana,
          titles: [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'pump' }],
          topCheckIn: {
            checkIn: members[0]?.checkIns[0]?.id,
            day: '2026-10-21',
            kind: 'trained',
            sport: 'run',
            photos: [],
            reactions: { cheer: 2 },
          },
        },
        {
          member: bo,
          titles: [{ title: '请假条文豪', speech: '周四的请假条写成了连载。', move: 'flat' }],
        },
      ],
    });
    expect(asked).toHaveLength(1);
    expect(asked[0]).not.toContain(cy);
    // Asked again, the same awards, without asking the model.
    expect(await awards.give({ squad, weekStart: week, members })).toStrictEqual(given);
    expect(await awards.find({ squad, weekStart: week })).toStrictEqual({
      status: 'given',
      awards: given,
    });
    expect(asked).toHaveLength(1);
  });

  it('asks once more when the first answer fails the checks', async () => {
    const bad = { ...reply, awards: reply.awards.slice(0, 1) };
    const { awards, asked } = setup([() => Promise.resolve(bad), () => Promise.resolve(reply)]);
    const [squad, ana, bo, cy] = [await newSquad(), member(), member(), member()];
    expect(
      await reasonOf(awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) })),
    ).toBe('ok');
    expect(asked).toHaveLength(2);
  });

  it('saves only the failed try and why when no answer passes, so the next run tries again', async () => {
    const down = setup([() => Promise.reject(new Error('down'))]);
    const [squad, ana, bo, cy] = [await newSquad(), member(), member(), member()];
    const members = weekOf([ana, bo, cy]);
    expect(await reasonOf(down.awards.give({ squad, weekStart: week, members }))).toBe(
      'AWARDS_WRITER_UNAVAILABLE',
    );
    expect(down.asked).toHaveLength(2);
    expect(await down.awards.find({ squad, weekStart: week })).toStrictEqual({
      status: 'failing',
      failures: { count: 1, lastError: 'Error: down' },
    });
    expect(await down.awards.claimWinners({ squad, weekStart: week })).toStrictEqual([]);
    const { awards } = setup();
    expect((await awards.give({ squad, weekStart: week, members })).members).toHaveLength(2);
  });

  it('gives a squad where nobody checked in no awards, without asking the model', async () => {
    const { awards, asked } = setup();
    const squad = await newSquad();
    const members = [{ member: member(), timeZone: 'UTC', checkIns: [] }];
    expect(await awards.give({ squad, weekStart: week, members })).toStrictEqual({
      version: 1,
      members: [],
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
    const [squad, ana, bo, cy] = [await newSquad(), member(), member(), member()];
    const members = weekOf([ana, bo, cy]);
    const [a, b] = await Promise.all([
      first.awards.give({ squad, weekStart: week, members }),
      second.awards.give({ squad, weekStart: week, members }),
    ]);
    expect(a).toStrictEqual(b);
    expect(await first.awards.find({ squad, weekStart: week })).toStrictEqual({
      status: 'given',
      awards: a,
    });
  });

  it('hands out the winners to tell once', async () => {
    const { awards } = setup();
    const [squad, ana, bo, cy] = [await newSquad(), member(), member(), member()];
    expect(await awards.claimWinners({ squad, weekStart: week })).toStrictEqual([]);
    await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    const claims = await Promise.all(
      [1, 2, 3].map(() => awards.claimWinners({ squad, weekStart: week })),
    );
    expect(claims.filter((claim) => claim.length > 0)).toStrictEqual([[ana, bo]]);
  });

  it('forgets a member in every squad’s awards, and only them', async () => {
    const { awards } = setup();
    const [ana, bo, cy] = [member(), member(), member()];
    const squads = [await newSquad(), await newSquad()];
    for (const squad of squads) {
      await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    }
    await awards.forget(ana);
    for (const squad of squads) {
      const kept = await awards.find({ squad, weekStart: week });
      expect(
        kept?.status === 'given' ? kept.awards.members.map((each) => each.member) : kept,
      ).toStrictEqual([bo]);
    }
  });

  it('hands out a squad’s week to nudge about once, with its failed tries, never once given', async () => {
    const quota = Object.assign(new Error('429 You exceeded your current quota'), {
      name: 'RateLimitError',
    });
    const down = setup([() => Promise.reject(new Error('unavailable', { cause: quota }))]);
    const [early, failing, given] = [await newSquad(), await newSquad(), await newSquad()];
    const members = weekOf([member(), member(), member()]);
    expect(await down.awards.claimNudge({ squad: early, weekStart: week })).toStrictEqual({
      count: 0,
    });
    expect(await down.awards.claimNudge({ squad: early, weekStart: week })).toBeUndefined();

    await reasonOf(down.awards.give({ squad: failing, weekStart: week, members }));
    await reasonOf(down.awards.give({ squad: failing, weekStart: week, members }));
    const nudges = await Promise.all(
      [1, 2, 3].map(() => down.awards.claimNudge({ squad: failing, weekStart: week })),
    );
    expect(nudges.filter((nudge) => nudge !== undefined)).toStrictEqual([
      { count: 2, lastError: 'RateLimitError: 429 You exceeded your current quota' },
    ]);

    const { awards } = setup();
    await awards.give({ squad: given, weekStart: week, members });
    expect(await awards.claimNudge({ squad: given, weekStart: week })).toBeUndefined();
    // A nudged week still takes its awards when a try passes.
    await awards.give({ squad: early, weekStart: week, members });
    expect((await awards.find({ squad: early, weekStart: week }))?.status).toBe('given');
  });
});
