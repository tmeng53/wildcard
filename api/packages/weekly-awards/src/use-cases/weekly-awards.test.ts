import { randomUUID } from 'node:crypto';

import { isAppError } from '@wildcard/errors';
import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresAwardSettings } from '../adapters/postgres-award-settings.js';
import {
  createPostgresAwardsStore,
  type WeeklyAwardTables,
} from '../adapters/postgres-awards-store.js';
import { MemberId, SquadId, type MemberWeek, type ModelReply } from '../domain/awards.js';
import type { PromptMeme } from '../domain/prompt.js';
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
  awards: [
    { member: 'A', titles: [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'pump' }] },
    {
      member: 'B',
      titles: [{ title: '请假条文豪', speech: '周四的请假条写成了连载。', move: 'flat' }],
    },
  ],
};

function setup(
  answers: (() => Promise<unknown>)[] = [() => Promise.resolve(reply)],
  {
    agreed = () => true,
    memes = [],
  }: { agreed?: (member: MemberId) => boolean; memes?: readonly PromptMeme[] } = {},
) {
  const asked: string[] = [];
  const settingsAsked: { model: string; instructions: string }[] = [];
  const model: LanguageModel = {
    answer: async ({ model, instructions, prompt, reply: shape }) => {
      const next = answers[Math.min(asked.length, answers.length - 1)];
      asked.push(prompt);
      settingsAsked.push({ model, instructions });
      if (next === undefined) throw new Error('no answer set');
      return shape.parse(await next());
    },
  };
  const consentAsked: (readonly MemberId[])[] = [];
  const awards = createWeeklyAwards({
    model,
    settings: createPostgresAwardSettings(db),
    store: createPostgresAwardsStore(db),
    aiConsented: (members) => {
      consentAsked.push(members);
      return Promise.resolve(members.filter(agreed));
    },
    memes: () => Promise.resolve(memes),
  });
  return { awards, asked, settingsAsked, consentAsked };
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
  { member: ana, timeZone: 'UTC', checkIns: [checkIn({ '❤️': 2 }), checkIn()] },
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
  it('hands the model the memes in use', async () => {
    const meme = { phrase: '对自己很好', meaning: '照顾好自己', background: '小红书上流行' };
    const { awards, asked } = setup(undefined, { memes: [meme] });
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    expect(asked[0]).toContain(
      '"memes":[{"phrase":"对自己很好","meaning":"照顾好自己","background":"小红书上流行"}]',
    );
  });

  it('gives titles to members who checked in, nothing to anyone who didn’t, once', async () => {
    const { awards, asked, settingsAsked } = setup();
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const members = weekOf([ana, bo, cy]);
    const given = await awards.give({ squad, weekStart: week, members });
    // The settings' model and instructions, and the moves as the settings describe them.
    expect(settingsAsked[0]?.model).toBe('openai/gpt-6-luna');
    expect(settingsAsked[0]?.instructions).toMatch(
      /^你在给一个朋友运动打卡 App 的小队写「本周颁奖」/u,
    );
    expect(asked[0]).toContain(
      '{"id":"pump","description":"握拳两下，第二下跳起来（拼、狠、坚持）"}',
    );
    expect(given).toStrictEqual({
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
            reactions: { '❤️': 2 },
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

  it('sends the model only the weeks of members who agreed to AI use, and awards only them', async () => {
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const { awards, asked, consentAsked } = setup(
      [() => Promise.resolve({ ...reply, awards: reply.awards.slice(0, 1) })],
      { agreed: (each) => each === ana },
    );
    const given = await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    expect(consentAsked).toStrictEqual([[ana, bo]]);
    expect(given.members.map(({ member: each }) => each)).toStrictEqual([ana]);
    expect(asked).toHaveLength(1);
    expect(asked[0]).toContain('"member":"A"');
    expect(asked[0]).not.toContain('"member":"B"');
  });

  it('sends comments only from members who agreed to AI use, asking about every writer once', async () => {
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const { awards, asked, consentAsked } = setup(undefined, { agreed: (each) => each !== cy });
    const members: MemberWeek[] = [
      {
        member: ana,
        timeZone: 'UTC',
        checkIns: [
          {
            ...checkIn(),
            comments: [
              { member: bo, text: '雨天也跑' },
              { member: cy, text: '不想给 AI 看' },
            ],
          },
        ],
      },
      { member: bo, timeZone: 'UTC', checkIns: [checkIn()] },
      { member: cy, timeZone: 'UTC', checkIns: [] },
    ];
    await awards.give({ squad, weekStart: week, members });
    expect(consentAsked).toStrictEqual([[ana, bo, cy]]);
    expect(asked[0]).toContain('雨天也跑');
    expect(asked[0]).not.toContain('不想给 AI 看');
  });

  it('asks the model nothing when nobody who checked in agreed to AI use', async () => {
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const { awards, asked } = setup(undefined, { agreed: () => false });
    expect(
      await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) }),
    ).toStrictEqual({ members: [] });
    expect(asked).toHaveLength(0);
  });

  it('asks once more when the first answer fails the checks', async () => {
    const bad = { ...reply, awards: reply.awards.slice(0, 1) };
    const { awards, asked } = setup([() => Promise.resolve(bad), () => Promise.resolve(reply)]);
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    expect(
      await reasonOf(awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) })),
    ).toBe('ok');
    expect(asked).toHaveLength(2);
  });

  it('saves only the failed try and why when no answer passes, so the next run tries again', async () => {
    const down = setup([() => Promise.reject(new Error('down'))]);
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const members = weekOf([ana, bo, cy]);
    expect(await reasonOf(down.awards.give({ squad, weekStart: week, members }))).toBe(
      'AWARDS_WRITER_UNAVAILABLE',
    );
    expect(down.asked).toHaveLength(2);
    expect(await down.awards.find({ squad, weekStart: week })).toStrictEqual({
      status: 'failing',
      failures: { count: 1, lastError: 'Error' },
    });
    expect(await down.awards.claimWinners({ squad, weekStart: week })).toStrictEqual([]);
    const { awards } = setup();
    expect((await awards.give({ squad, weekStart: week, members })).members).toHaveLength(2);
  });

  it('gives a squad where nobody checked in no awards, without asking the model', async () => {
    const { awards, asked } = setup();
    const squad = await newSquad();
    const members = [{ member: await member(), timeZone: 'UTC', checkIns: [] }];
    expect(await awards.give({ squad, weekStart: week, members })).toStrictEqual({
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
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
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
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    expect(await awards.claimWinners({ squad, weekStart: week })).toStrictEqual([]);
    await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
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
      await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
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
    await expect(awards.give({ squad, weekStart: week, members })).rejects.toThrow();
    expect(await awards.find({ squad, weekStart: week })).toBeUndefined();
    const fresh = members.filter(({ member: each }) => each !== bo);
    const alone = setup([() => Promise.resolve({ ...reply, awards: reply.awards.slice(0, 1) })]);
    const given = await alone.awards.give({ squad, weekStart: week, members: fresh });
    expect(given.members.map((each) => each.member)).toStrictEqual([ana]);
  });

  it('keeps a missing model key by name, so the admins know to set it', async () => {
    const off = setup([
      () =>
        Promise.reject(new AwardsWriterUnavailableError({ cause: new AwardsModelMissingError() })),
    ]);
    const squad = await newSquad();
    const members = weekOf([await member(), await member(), await member()]);
    await reasonOf(off.awards.give({ squad, weekStart: week, members }));
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

    await reasonOf(down.awards.give({ squad, weekStart: week, members }));
    const nudges = await Promise.all([nudge(), nudge(), nudge()]);
    // The provider's name, status and code, never its message.
    const lastError = 'RateLimitError 429 insufficient_quota';
    expect(nudges.filter((each) => each !== undefined)).toStrictEqual([{ count: 1, lastError }]);
    await reasonOf(down.awards.give({ squad, weekStart: week, members }));
    expect(await nudge()).toStrictEqual({ count: 2, lastError });
    expect(await nudge()).toBeUndefined();

    const { awards } = setup();
    await awards.give({ squad: given, weekStart: week, members });
    expect(await awards.claimNudge({ squad: given, weekStart: week })).toBeUndefined();
    // A nudged week still takes its awards when a try passes, and isn't nudged after.
    await awards.give({ squad, weekStart: week, members });
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
    await reasonOf(awards.give({ squad, weekStart: week, members }));
    expect(await awards.find({ squad, weekStart: week })).toStrictEqual({
      status: 'failing',
      failures: { count: 1, lastError: 'FailedChecks' },
    });
  });
});
