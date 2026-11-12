import { randomUUID } from 'node:crypto';

import { isAppError } from '@wildcard/errors';
import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresAwardSettings } from '../adapters/postgres-award-settings.js';
import { createPostgresWeekStoryStore } from '../adapters/postgres-week-story-store.js';
import {
  createPostgresAwardsStore,
  type WeeklyAwardTables,
} from '../adapters/postgres-awards-store.js';
import { MemberId, SquadId, type MemberWeek, type ModelReply } from '../domain/awards.js';

type ReplyTitle = NonNullable<ModelReply['awards'][string]>[number];
import type { SportGlyph } from '../domain/badges.js';
import type { PromptMeme } from '../domain/prompt.js';
import { WeekStart } from '../domain/schedule.js';
import { AwardsModelMissingError, AwardsWriterUnavailableError } from '../errors.js';
import type { LanguageModel, ModelPayer } from '@wildcard/language-model';
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

/** A badge from the catalog the migrations seed. */
const badge = { shape: 'shield', colour: 'track', glyph: 'sun.max.fill' };

const reply: ModelReply = {
  version: 1,
  awards: {
    A: [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'pump', badge }],
    B: [{ title: '请假条文豪', speech: '周四的请假条写成了连载。', move: 'flat', badge }],
  },
  ending: { headline: '差一点', line: ' 再练三天，\n 计划就满了 ' },
};

/** `reply` with each title changed by `change`. */
const retitled = (change: (title: ReplyTitle) => ReplyTitle): ModelReply => ({
  ...reply,
  awards: Object.fromEntries(
    Object.entries(reply.awards).map(([key, titles]) => [key, titles?.map(change) ?? null]),
  ),
});

/** `reply` for A alone. */
const onlyA: ModelReply = { ...reply, awards: { A: reply.awards.A ?? [] } };

/** `reply` with A's title blank once trimmed: it passes the schema, not the checks. */
const blankTitle: ModelReply = retitled((title) => ({ ...title, title: ' ' }));

function setup(
  answers: (() => Promise<unknown>)[] = [() => Promise.resolve(reply)],
  {
    agreed = () => true,
    memes = [],
    sportGlyphs = [],
  }: {
    agreed?: (member: MemberId) => boolean;
    memes?: readonly PromptMeme[];
    sportGlyphs?: readonly SportGlyph[];
  } = {},
) {
  const asked: string[] = [];
  const settingsAsked: { model: string; instructions: string; payer: ModelPayer }[] = [];
  const model: LanguageModel = {
    answer: async ({ model, instructions, prompt, reply: shape, payer }) => {
      const next = answers[Math.min(asked.length, answers.length - 1)];
      asked.push(prompt);
      settingsAsked.push({ model, instructions, payer });
      if (next === undefined) throw new Error('no answer set');
      return shape.parse(await next());
    },
  };
  const consentAsked: (readonly MemberId[])[] = [];
  const awards = createWeeklyAwards({
    model,
    settings: createPostgresAwardSettings(db),
    store: createPostgresAwardsStore(db),
    stories: createPostgresWeekStoryStore(db),
    aiConsented: (members) => {
      consentAsked.push(members);
      return Promise.resolve(members.filter(agreed));
    },
    memes: () => Promise.resolve(memes),
    sportGlyphs: () => Promise.resolve(sportGlyphs),
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
    // Counted to the squad, whose AI budget pays.
    expect(settingsAsked[0]?.payer).toStrictEqual({ squad });
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
          titles: [{ title: '雨中狠人', speech: '周三下着雨还去跑了。', move: 'pump', badge }],
        },
        {
          member: bo,
          titles: [
            { title: '请假条文豪', speech: '周四的请假条写成了连载。', move: 'flat', badge },
          ],
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

  it('has the model write the last page’s words from the squad’s days, kept with the awards', async () => {
    const { awards, asked } = setup();
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const members = weekOf([ana, bo, cy]);
    const given = await awards.give({
      squad,
      weekStart: week,
      members,
      ending: { done: 19, plan: 22 },
    });
    expect(asked[0]).toContain('"squad":{"trainings":19,"goal":22}');
    expect(given.ending).toStrictEqual({
      version: 1,
      headline: '差一点',
      line: '再练三天， 计划就满了',
    });
    expect(await awards.find({ squad, weekStart: week })).toStrictEqual({
      status: 'given',
      awards: given,
    });
  });

  it('keeps no last-page words for a squad that trained no day', async () => {
    const { awards, asked } = setup();
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const given = await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    expect(asked[0]).not.toContain('"squad"');
    expect(given.ending).toBeUndefined();
  });

  it('takes blank last-page words without asking again when the squad trained no day', async () => {
    const { awards, asked } = setup([
      () => Promise.resolve({ ...reply, ending: { headline: '稳了', line: '   ' } }),
    ]);
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const given = await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    expect(asked).toHaveLength(1);
    expect(given.members).toHaveLength(2);
    expect(given.ending).toBeUndefined();
  });

  it('keeps the titles when the last page’s line comes back blank, leaving the page its own words', async () => {
    const { awards, asked } = setup([
      () => Promise.resolve({ ...reply, ending: { headline: '稳了', line: '   ' } }),
    ]);
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const given = await awards.give({
      squad,
      weekStart: week,
      members: weekOf([ana, bo, cy]),
      ending: { done: 23, plan: 22 },
    });
    expect(asked).toHaveLength(1);
    expect(given.ending).toBeUndefined();
    expect(given.members).toHaveLength(2);
  });

  it('hands the model the badge catalog and keeps the badge it picks on each title', async () => {
    const { awards, asked } = setup();
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    expect(asked[0]).toContain('{"id":"shield","meaning":"盾牌：守住了、扛住了、说到做到"}');
    expect(asked[0]).toContain('{"id":"sun.max.fill","meaning":"太阳：早起、白天练"}');
    // The model picks a colour by what it means; its tone is only the app's.
    expect(asked[0]).toContain('{"id":"track","meaning":"跑道红：热烈、速度、上头"}');
    expect(asked[0]).not.toContain('#E65345');
    const boards = await awards.boards([ana, cy]);
    expect(boards.get(ana)).toStrictEqual([
      {
        title: '雨中狠人',
        badge: { ...badge, tone: '#E65345' },
        weeks: [{ squad, weekStart: week, speech: '周三下着雨还去跑了。' }],
      },
    ]);
    expect(boards.get(cy)).toStrictEqual([]);
    expect(await awards.titlesWon(ana)).toStrictEqual({
      count: 1,
      latest: { title: '雨中狠人', times: 1 },
    });
  });

  it('offers every sport’s icon as a glyph, and keeps a badge that wears one', async () => {
    const running = retitled((title) => ({
      ...title,
      badge: { ...badge, glyph: 'figure.outdoor.cycle' },
    }));
    const { awards, asked } = setup([() => Promise.resolve(running)], {
      sportGlyphs: [{ id: 'figure.outdoor.cycle', meaning: '骑行（运动）' }],
    });
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const given = await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    expect(asked).toHaveLength(1);
    expect(asked[0]).toContain('{"id":"figure.outdoor.cycle","meaning":"骑行（运动）"}');
    expect(given.members[0]?.titles[0]?.badge?.glyph).toBe('figure.outdoor.cycle');
  });

  it('refuses a badge the catalog doesn’t offer, asking once more', async () => {
    const offCatalog = retitled((title) => ({ ...title, badge: { ...badge, glyph: 'gear' } }));
    const { awards, asked } = setup([
      () => Promise.resolve(offCatalog),
      () => Promise.resolve(reply),
    ]);
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const given = await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    expect(asked).toHaveLength(2);
    expect(given.members[0]?.titles[0]?.badge).toStrictEqual(badge);
  });

  it('sends the model only the weeks of members who agreed to AI use, and awards only them', async () => {
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const { awards, asked, consentAsked } = setup([() => Promise.resolve(onlyA)], {
      agreed: (each) => each === ana,
    });
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

  it('asks once more when the first answer is off its schema', async () => {
    // A letter nobody in the prompt goes by.
    const bad = { ...reply, awards: { ...reply.awards, C: reply.awards.A } };
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
    expect(await down.awards.claimReadyPush({ squad, weekStart: week })).toBe(false);
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
  });

  it('keeps one set of awards when two runs write at once', async () => {
    const other = retitled((title) => ({ ...title, title: `${title.title.slice(0, 4)}二` }));
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

  it('hands out the squad’s ready push once, after the awards are written', async () => {
    const { awards } = setup();
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    expect(await awards.claimReadyPush({ squad, weekStart: week })).toBe(false);
    await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    const claims = await Promise.all(
      [1, 2, 3].map(() => awards.claimReadyPush({ squad, weekStart: week })),
    );
    expect(claims.filter(Boolean)).toHaveLength(1);
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
    const alone = setup([() => Promise.resolve(onlyA)]);
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

  it('drops a blank title and leaves out whoever the model gives none, never failing for it', async () => {
    const { awards, asked } = setup([() => Promise.resolve(blankTitle)]);
    const [squad, ana, bo, cy] = [await newSquad(), await member(), await member(), await member()];
    const given = await awards.give({ squad, weekStart: week, members: weekOf([ana, bo, cy]) });
    expect(asked).toHaveLength(1);
    expect(given.members).toStrictEqual([]);

    const { awards: other } = setup([
      () => Promise.resolve({ ...reply, awards: { ...reply.awards, A: null } }),
    ]);
    const [squad2, di, ed, fay] = [
      await newSquad(),
      await member(),
      await member(),
      await member(),
    ];
    const some = await other.give({
      squad: squad2,
      weekStart: week,
      members: weekOf([di, ed, fay]),
    });
    expect(some.members.map((each) => each.member)).toStrictEqual([ed]);
  });
});

describe('the frozen 战报', () => {
  const days = Array.from({ length: 7 }, (_, index) => ({
    day: `2026-10-${String(19 + index)}`,
    kind: 'none' as const,
  }));
  const part = (member: MemberId) => ({
    member,
    version: 1 as const,
    character: null,
    checkedIn: true,
    plannedDays: 5,
    trainedDays: 1,
    days,
    healthyMeals: 0,
    cheatMeals: 1,
    reactionsReceived: 2,
    reachedAt: '2026-10-22T09:00:00.000Z',
  });

  it('is kept once: a second freeze leaves the first, and a deleted account takes its part', async () => {
    const { awards } = setup();
    const [squad, ana, bo] = [await newSquad(), await member(), await member()];
    expect(await awards.story({ squad, weekStart: week })).toBeUndefined();
    const note = randomUUID();
    await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
      values (${note}, ${ana}, '2026-10-21', now(), 'disclaimer', '{"version":1}')`.execute(db);
    const story = {
      squad,
      weekStart: week,
      story: { version: 1 as const, name: 'squad', scene: 'gym', ending: { done: 1, plan: 10 } },
      members: [
        {
          ...part(ana),
          bestDisclaimer: { checkIn: note, text: '今天腿说不', reactions: 2 },
        },
        part(bo),
      ],
    };
    expect(await awards.freezeStory(story)).toStrictEqual(story);
    const later = {
      ...story,
      story: { version: 1 as const, name: 'renamed', scene: 'pool' },
      members: [part(bo)],
    };
    expect(await awards.freezeStory(later)).toStrictEqual(story);
    // Deleting the post takes its words with it; deleting the account, the rest of their part.
    await sql`delete from public.check_ins where id = ${note}`.execute(db);
    expect((await awards.story({ squad, weekStart: week }))?.members).toStrictEqual([
      part(ana),
      part(bo),
    ]);
    await sql`delete from auth.users where id = ${ana}`.execute(db);
    expect(await awards.story({ squad, weekStart: week })).toStrictEqual({
      ...story,
      members: [part(bo)],
    });
    await expect(
      sql`delete from public.week_story_members where member_id = ${bo}`.execute(db),
    ).rejects.toThrow(/frozen/u);
  });
});
