import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresCoachCatalog } from '../adapters/postgres-coach-catalog.js';
import { createPostgresCoachHiring } from '../adapters/postgres-coach-hiring.js';
import {
  createPostgresCoachSettings,
  type CoachTables,
} from '../adapters/postgres-coach-settings.js';
import {
  createPostgresCoachActivity,
  createPostgresCoachNoteDelivery,
  createPostgresCoachReport,
  createPostgresCoachStores,
} from '../adapters/postgres-coach-stores.js';
import { CoachId } from '../domain/coach.js';
import { MemberId, SquadId } from '../domain/settings.js';
import {
  CoachAlreadyHiredError,
  CoachNoteNoChallengeError,
  CoachNoteNotFoundError,
  CoachNotOfferedError,
  CoachSquadNotFoundError,
  NoCoachHiredError,
} from '../errors.js';
import { weekText, type SquadWeek } from '../domain/squad-week.js';
import type {
  AgentRun,
  CoachAgent,
  CoachGifting,
  CoachHiringStore,
  CoachMemberFacts,
  CoachMemes,
  CoachPhotoUrls,
  CoachTool,
  CoachWeather,
} from '../ports.js';
import { createCoachActivity } from './coach-activity.js';
import { createCoachNoteDelivery } from './coach-note-delivery.js';
import { createCoachHiring } from './coach-hiring.js';
import { createCoachSettings } from './coach-settings.js';
import { createCoachWakes, type CoachAnswered, type CoachReplied } from './coach-wakes.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Each test works inside a
// transaction it rolls back, so the seeded settings stay as they are for the other tests.
const db = new Kysely<CoachTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

class RolledBack extends Error {}

/** 10:00 in New York on a Sunday: past the daily wake's hour. */
const now = new Date('2026-11-01T15:00:00Z');

interface Fixture {
  readonly trx: Kysely<CoachTables>;
  readonly squad: SquadId;
  readonly mia: string;
  readonly leo: string;
  readonly checkIn: string;
  readonly week: SquadWeek;
}

/** A squad of two that hired 小混, with one check-in made 10 minutes ago, and coaching on. */
async function rolledBack(test: (fixture: Fixture) => Promise<void>) {
  // The test's own failure, not the rollback, when it has one.
  await db
    .transaction()
    .execute(async (trx) => {
      const [mia, leo, squadId, checkIn] = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
      // Only this squad has a coach here: squads other test files hired one for (and may leave
      // behind) would otherwise wake too, since the job looks at every squad with a coach.
      await sql`delete from public.squad_coaches`.execute(trx);
      for (const id of [mia, leo]) {
        await sql`insert into auth.users (id, email) values (${id}, ${`${id}@example.com`})`.execute(
          trx,
        );
      }
      await sql`insert into public.squads (id, name, invite_code) values (${squadId}, 'squad', ${squadId})`.execute(
        trx,
      );
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${checkIn}, ${mia}, '2026-11-01', ${new Date(now.getTime() - 10 * 60_000)}, 'trained',
          '{"version": 1, "sport": "run"}')`.execute(trx);
      const squad = SquadId.parse(squadId);
      await createCoachSettings({ store: createPostgresCoachSettings(trx) }).change(
        { coaching: true, inputMicrosPerMillion: 250_000, outputMicrosPerMillion: 2_000_000 },
        MemberId.parse(mia),
      );
      // A run wakes every squad with a coach: other test files' squads, committed while this
      // one runs, would count too.
      await sql`delete from public.squad_coaches`.execute(trx);
      await createCoachHiring({
        hiring: createPostgresCoachHiring(trx),
        catalog: createPostgresCoachCatalog(trx),
      }).hire({ squad, coach: CoachId.parse('xiaohun'), by: MemberId.parse(mia) });
      const week: SquadWeek = {
        weekStart: '2026-10-26',
        members: [{ member: mia, nickname: '米亚' }, { member: leo }],
        checkIns: [
          {
            id: checkIn,
            member: mia,
            day: '2026-11-01',
            createdAt: new Date(now.getTime() - 10 * 60_000),
            kind: 'trained',
            sport: '跑步',
            reactedBy: [],
            comments: [],
          },
        ],
      };
      await test({ trx, squad, mia, leo, checkIn, week });
      throw new RolledBack();
    })
    .catch((error: unknown) => {
      if (!(error instanceof RolledBack)) throw error;
    });
}

/** One step a scripted agent takes: a tool call, with what the tool answered checked. */
interface Step {
  readonly tool: string;
  readonly input: Record<string, unknown>;
}

/**
 * An agent that calls tools as a model would, by name and with JSON arguments, from a script
 * per task, and records every task and every answer.
 */
function scriptedAgent(script: (task: string) => readonly Step[] | 'fail') {
  const runs: { task: string; instructions: string; tools: string[]; answers: string[] }[] = [];
  const agent: CoachAgent = {
    async run({ instructions, task, tools }): Promise<AgentRun> {
      const steps = script(task);
      const usage = { requests: 2, inputTokens: 12_000, cachedInputTokens: 0, outputTokens: 800 };
      const answers: string[] = [];
      runs.push({ task, instructions, tools: tools.map(({ name }) => name), answers });
      if (steps === 'fail') return { ok: false, usage, error: 'ModelBehaviorError: no' };
      for (const step of steps) {
        const tool: CoachTool | undefined = tools.find(({ name }) => name === step.tool);
        const answer = tool === undefined ? `no tool ${step.tool}` : await tool.run(step.input);
        answers.push(
          typeof answer === 'string' ? answer : [answer.text, ...answer.images].join(' '),
        );
      }
      return { ok: true, usage };
    },
  };
  return { agent, runs };
}

/**
 * The coach at `at`, on the fixture's squad, whose week is `week` (else the fixture's, for
 * every week) and whose members all agreed to AI use unless `consented` says who did.
 */
function wakes(
  { trx, squad, week }: Fixture,
  {
    agent,
    at = now,
    weeks,
    consented,
    replied,
    answered,
    photoUrls,
    memberFacts,
    wantNotes,
    memes,
    gifting,
    weatherOf,
  }: {
    readonly agent: CoachAgent;
    readonly at?: Date;
    readonly weeks?: Readonly<Record<string, SquadWeek>>;
    readonly consented?: readonly string[];
    readonly replied?: CoachReplied;
    readonly answered?: CoachAnswered;
    readonly photoUrls?: CoachPhotoUrls;
    readonly memberFacts?: CoachMemberFacts;
    readonly wantNotes?: (members: readonly string[]) => Promise<readonly string[]>;
    readonly memes?: CoachMemes;
    readonly gifting?: CoachGifting;
    readonly weatherOf?: CoachWeather;
  },
) {
  const stores = createPostgresCoachStores(trx);
  return createCoachWakes({
    settings: createPostgresCoachSettings(trx),
    catalog: createPostgresCoachCatalog(trx),
    stores,
    // Already in the test's transaction, which is rolled back at the end.
    transaction: (work) => work(stores),
    agent,
    squadWeek: ({ weekStart }) =>
      Promise.resolve(
        weeks === undefined
          ? week
          : (weeks[weekStart] ?? { weekStart, members: week.members, checkIns: [] }),
      ),
    aiConsented: (members) =>
      Promise.resolve(
        consented === undefined ? members : members.filter((member) => consented.includes(member)),
      ),
    hiring: ownSquadOnly(createPostgresCoachHiring(trx), squad),
    clock: () => at,
    ...(replied === undefined ? {} : { replied }),
    ...(answered === undefined ? {} : { answered }),
    ...(photoUrls === undefined ? {} : { photoUrls }),
    ...(memberFacts === undefined ? {} : { memberFacts }),
    ...(wantNotes === undefined ? {} : { wantNotes }),
    ...(memes === undefined ? {} : { memes }),
    ...(gifting === undefined ? {} : { gifting }),
    ...(weatherOf === undefined ? {} : { weatherOf }),
  });
}

/**
 * The hiring store, seeing only the fixture's squad among the squads with a coach: other
 * test files commit squads that keep theirs, and a run would wake those too.
 */
function ownSquadOnly(hiring: CoachHiringStore, squad: SquadId): CoachHiringStore {
  return {
    ...hiring,
    hired: async () =>
      new Map([...(await hiring.hired())].filter(([hiredSquad]) => hiredSquad === squad)),
  };
}

/** A comment under the fixture's check-in, as the check-ins module saves it. */
async function commentOn(
  { trx, checkIn }: Fixture,
  {
    member,
    text,
    at,
    toCoach,
    mentionsCoach,
  }: {
    readonly member: string;
    readonly text: string;
    readonly at: Date;
    readonly toCoach?: string;
    readonly mentionsCoach?: string;
  },
) {
  const id = randomUUID();
  await sql`insert into public.check_in_comments (id, check_in_id, member_id, text, reply_to_coach, mentions_coach, commented_at)
    values (${id}, ${checkIn}, ${member}, ${text}, ${toCoach ?? null}, ${mentionsCoach ?? null}, ${at})`.execute(
    trx,
  );
  return {
    id,
    member,
    text,
    at,
    ...(toCoach === undefined ? {} : { toCoach }),
    ...(mentionsCoach === undefined ? {} : { mentionsCoach }),
  };
}

describe('the coach', () => {
  it('does nothing while coaching is off', async () => {
    const { agent, runs } = scriptedAgent(() => []);
    const run = await createCoachWakes({
      settings: createPostgresCoachSettings(db),
      catalog: createPostgresCoachCatalog(db),
      stores: createPostgresCoachStores(db),
      transaction: () => Promise.reject(new Error('nothing to save')),
      agent,
      squadWeek: () => Promise.reject(new Error('no squad to read')),
      aiConsented: () => Promise.reject(new Error('no one to ask')),
      hiring: createPostgresCoachHiring(db),
      clock: () => now,
    }).run();
    expect(run).toStrictEqual({ coaching: false, squads: 0, queued: 0, done: 0, failed: 0 });
    expect(runs).toHaveLength(0);
  });

  it('writes no morning note to a member who switched the coach off', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => [
        { tool: 'note_to', input: { member: '队员2', text: '今天走走' } },
      ]);
      const asked: (readonly string[])[] = [];
      const wantNotes = (members: readonly string[]) => {
        asked.push(members);
        return Promise.resolve(members.filter((member) => member !== fixture.leo));
      };

      await wakes(fixture, { agent, wantNotes }).run();

      const daily = runs.find(({ task }) => task.includes('新的一天'));
      expect(asked).toStrictEqual([[fixture.mia, fixture.leo]]);
      expect(daily?.task).toContain('今天给这些人各写一张便条：\n- 队员1：');
      expect(daily?.task).not.toContain('- 队员2：这周');
      expect(daily?.answers).toStrictEqual(['不能给 队员2 写便条；能写的是：队员1。']);
    });
  });

  it('wakes for a check-in and for the day, keeps its memory and its line, and counts tokens', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, leo } = fixture;
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('新的一天')
          ? [
              { tool: 'squad_week', input: {} },
              { tool: 'post_note', input: { text: '队员1 周日也跑了' } },
              { tool: 'post_note', input: { text: '  周日也跑了，米亚是认真的  ' } },
              { tool: 'note_to', input: { member: '队员1', text: '周日那趟我看见了' } },
              { tool: 'note_to', input: { member: '队员3', text: '你好' } },
              { tool: 'note_to', input: { member: '队员2', text: '队员2 今天动一动？' } },
              { tool: 'note_to', input: { member: '队员2', text: '今天动一动？走走也算' } },
              { tool: 'note_to', input: { member: '队员1', text: ' 周日那趟跑得真稳 ' } },
            ]
          : [
              { tool: 'remember', input: { path: 'memory.md', fact: ' 队员1 周日跑步 ' } },
              {
                tool: 'edit_file',
                input: { path: 'people/队员2.md', find: '', replace: '还没打卡过' },
              },
              {
                tool: 'edit_file',
                input: { path: 'people/队员3.md', find: '', replace: '没这个人' },
              },
              { tool: 'post_note', input: { text: '不该有这个工具' } },
              { tool: 'reply', input: { text: '队员1 周日还跑' } },
              { tool: 'reply', input: { text: '跑'.repeat(101) } },
              { tool: 'reply', input: { text: '周日也跑？' } },
              { tool: 'reply', input: { text: '  周日也跑，腿还在吗  ' } },
              { tool: 'react', input: { emoji: '💩' } },
              { tool: 'react', input: { emoji: '🔥' } },
            ],
      );
      const told: Parameters<CoachReplied>[0][] = [];
      const replied: CoachReplied = (reply) => {
        told.push(reply);
        return Promise.resolve();
      };

      // The check-in, the night's dream (with nothing from yesterday to tidy) and the day.
      expect(await wakes(fixture, { agent, replied }).run()).toStrictEqual({
        coaching: true,
        squads: 1,
        queued: 3,
        done: 3,
        failed: 0,
      });
      // Told once, after the reply was saved, for the server to tell its author.
      expect(told).toStrictEqual([
        {
          squad,
          checkIn: fixture.checkIn,
          author: fixture.mia,
          coach: 'xiaohun',
          text: '周日也跑，腿还在吗',
          emoji: '🔥',
          mentions: [],
        },
      ]);

      // The check-in's wake ran first: it may edit files and reply and react to the check-in, but
      // not post on the 战术板; the daily wake posts but replies to nothing.
      expect(runs.map(({ tools }) => tools)).toStrictEqual([
        ['squad_week', 'remember', 'edit_file', 'reply', 'react'],
        ['squad_week', 'remember', 'edit_file', 'post_note', 'note_to'],
      ]);
      expect(runs[0]?.task).toContain('队员1 训练 跑步');
      expect(runs[0]?.answers).toStrictEqual([
        '记下了，在 memory.md。',
        '已改好，people/队员2.md 现在 5 字。',
        '没有 people/队员3.md 这个文件；能用的文件见任务里的列表。',
        'no tool post_note',
        '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。',
        '太长了：101 字，最多 100 字。',
        '已回复。',
        '已换成这句。',
        expect.stringContaining('参数不对'),
        '已点 🔥。',
      ]);
      expect(runs[1]?.answers.slice(1)).toStrictEqual([
        '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。',
        '已写上战术板。',
        '便条写好了，给 队员1。',
        '不能给 队员3 写便条；能写的是：队员1、队员2。',
        '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。',
        '便条写好了，给 队员2。',
        '已换成这张，给 队员1。',
      ]);
      // Every member who agreed to AI use gets a note, whether or not they checked in.
      expect(runs[1]?.task).toContain(
        '今天给这些人各写一张便条：\n- 队员1：这周已经练了 1 天。 用简体中文写。\n- 队员2：这周已经练了 0 天。 用简体中文写。',
      );
      // With yesterday's posts, here none.
      expect(runs[1]?.task).toContain('昨天（周六）小队没人发动态。');
      expect(runs[0]?.task).not.toContain('便条');
      // The daily wake sees what the first one remembered, and the instructions are 小混's.
      expect(runs[1]?.task).toContain('【memory.md】\n- 队员1 周日跑步');
      expect(runs[1]?.task).toContain('过去一天没人在打卡下面和你说话。');
      expect(runs[1]?.instructions).toContain('你是小混');
      expect(runs[1]?.instructions).toContain('不提谁没打卡');
      // How each wake goes is in the instructions, the same every time, so it can be cached.
      expect(runs[1]?.instructions).toContain('你会在四种时候醒来');
      // The 简历 is for the app only: the model never reads the coach's missing license.
      expect(runs[1]?.instructions).not.toContain('证还没考下来');
      expect(runs[0]?.instructions).toBe(runs[1]?.instructions);

      // A member's page is stored by their id, never by 队员N.
      const files = await sql<{ path: string; body: string; member_id: string | null }>`
        select path, body, member_id from public.coach_files where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(files.rows).toStrictEqual([
        // The first wake starts the squad's file from who is in it.
        {
          path: 'squad.md',
          body: `# 小队\n队员（昵称会变，以 squad_week 为准）：\n- {队员:${fixture.mia}}：昵称「米亚」\n- {队员:${leo}}`,
          member_id: null,
        },
        // Members named in a file are stored by id, so a name follows them when 队员N shifts.
        { path: 'memory.md', body: `- {队员:${fixture.mia}} 周日跑步`, member_id: null },
        { path: `people/${leo}.md`, body: '还没打卡过', member_id: leo },
      ]);
      const notes = await sql<{ day: string; text: string; coach_id: string }>`
        select to_char(day, 'YYYY-MM-DD') as day, text, coach_id from public.coach_notes where squad_id = ${squad}`.execute(
        trx,
      );
      expect(notes.rows).toStrictEqual([
        { day: '2026-11-01', text: '周日也跑了，米亚是认真的', coach_id: 'xiaohun' },
      ]);
      // The check-in's reply, its last line and emoji, never pushed.
      const replies = await sql<{
        check_in_id: string;
        text: string;
        emoji: string;
        coach_id: string;
      }>`
        select check_in_id, text, emoji, coach_id from public.coach_replies where squad_id = ${squad}`.execute(
        trx,
      );
      expect(replies.rows).toStrictEqual([
        {
          check_in_id: fixture.checkIn,
          text: '周日也跑，腿还在吗',
          emoji: '🔥',
          coach_id: 'xiaohun',
        },
      ]);
      // What members read: the newest line and the replies to the check-ins they ask about.
      const activity = createCoachActivity({ store: createPostgresCoachActivity(trx) });
      const xiaohun = { id: 'xiaohun', name: '小混', look: 'xiaohun' };
      const said = await activity.squad({
        squad,
        checkIns: [fixture.checkIn.toUpperCase(), randomUUID()],
      });
      expect(
        [said.note?.at, ...said.replies.map(({ at }) => at)].every((at) => at instanceof Date),
      ).toBe(true);
      expect({
        note: said.note === undefined ? undefined : { ...said.note, at: 'at' },
        replies: said.replies.map((reply) => ({ ...reply, at: 'at' })),
      }).toStrictEqual({
        note: {
          day: '2026-11-01',
          text: '周日也跑了，米亚是认真的',
          coach: xiaohun,
          at: 'at',
        },
        replies: [
          {
            checkIn: fixture.checkIn,
            coach: xiaohun,
            text: '周日也跑，腿还在吗',
            emoji: '🔥',
            mentions: [],
            at: 'at',
          },
        ],
      });
      expect(await activity.squad({ squad, checkIns: [] })).toMatchObject({ replies: [] });

      // One morning note a member, each only for them, waiting for their morning.
      const memberNotes = await sql<{ member_id: string; day: string; text: string }>`
        select member_id, to_char(day, 'YYYY-MM-DD') as day, text from public.coach_member_notes
        where squad_id = ${squad} order by member_id`.execute(trx);
      expect(memberNotes.rows).toStrictEqual(
        [
          { member_id: fixture.mia, day: '2026-11-01', text: '周日那趟跑得真稳' },
          { member_id: leo, day: '2026-11-01', text: '今天动一动？走走也算' },
        ].toSorted((a, b) => a.member_id.localeCompare(b.member_id)),
      );
      // Not on 今天 before it reached them; then only the reader's own.
      expect(
        (await activity.squad({ squad, checkIns: [], reader: fixture.mia })).memberNote,
      ).toBeUndefined();
      const delivery = createCoachNoteDelivery({ store: createPostgresCoachNoteDelivery(trx) });
      const waiting = await delivery.waiting(now);
      expect(
        waiting
          .map(({ member, text, coachName, day }) => ({ member, text, coachName, day }))
          .toSorted((a, b) => a.member.localeCompare(b.member)),
      ).toStrictEqual(
        [
          { member: fixture.mia, text: '周日那趟跑得真稳', coachName: '小混', day: '2026-11-01' },
          { member: leo, text: '今天动一动？走走也算', coachName: '小混', day: '2026-11-01' },
        ].toSorted((a, b) => a.member.localeCompare(b.member)),
      );
      const miaNote = waiting.find(({ member }) => member === fixture.mia);
      if (miaNote === undefined) throw new Error('no note for mia');
      expect(await delivery.delivered(miaNote.id)).toBe(true);
      expect(await delivery.delivered(miaNote.id)).toBe(false);
      expect((await delivery.waiting(now)).map(({ member }) => member)).toStrictEqual([leo]);
      const mine = await activity.squad({ squad, checkIns: [], reader: fixture.mia });
      expect({ ...mine.memberNote, at: 'at' }).toStrictEqual({
        id: miaNote.id,
        day: '2026-11-01',
        text: '周日那趟跑得真稳',
        coach: xiaohun,
        at: 'at',
      });
      expect(
        (await activity.squad({ squad, checkIns: [], reader: leo })).memberNote,
      ).toBeUndefined();
      // Put away on one phone, it shows on none; only its own member can.
      await expect(
        activity.putAway({ squad, member: leo, note: miaNote.id }),
      ).rejects.toBeInstanceOf(CoachNoteNotFoundError);
      await activity.putAway({ squad, member: fixture.mia, note: miaNote.id });
      await activity.putAway({ squad, member: fixture.mia, note: miaNote.id });
      expect(
        (await activity.squad({ squad, checkIns: [], reader: fixture.mia })).memberNote,
      ).toBeUndefined();
      // Never put away, it is gone from 今天 once its day is over (the bell keeps it).
      const leoNote = waiting.find(({ member }) => member === leo);
      if (leoNote === undefined) throw new Error('no note for leo');
      await delivery.delivered(leoNote.id);
      expect((await activity.squad({ squad, checkIns: [], reader: leo })).memberNote?.text).toBe(
        '今天动一动？走走也算',
      );
      expect(
        (
          await activity.squad({
            squad,
            checkIns: [],
            reader: leo,
            now: new Date(Date.now() + 19 * 60 * 60_000),
          })
        ).memberNote,
      ).toBeUndefined();
      // 12,000 in at $0.25 and 800 out at $2 per million tokens: 4,600 millionths a wake.
      const usage = await sql<{ requests: number; input_tokens: string; cost_micros: string }>`
        select requests, input_tokens, cost_micros from public.coach_usage where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(usage.rows).toStrictEqual([
        { requests: 2, input_tokens: '12000', cost_micros: '4600' },
        { requests: 2, input_tokens: '12000', cost_micros: '4600' },
      ]);

      // Run again: nothing new to wake for, and nothing runs twice.
      expect(
        await wakes(fixture, { agent, at: new Date(now.getTime() + 10 * 60_000) }).run(),
      ).toStrictEqual({
        coaching: true,
        squads: 1,
        queued: 0,
        done: 0,
        failed: 0,
      });
      expect(runs).toHaveLength(2);
      // Once the coach is fired, its note leaves 今天 too (the bell keeps it).
      await createCoachHiring({
        hiring: createPostgresCoachHiring(trx),
        catalog: createPostgresCoachCatalog(trx),
      }).fire({ squad, by: MemberId.parse(fixture.mia) });
      expect(
        (await activity.squad({ squad, checkIns: [], reader: leo })).memberNote,
      ).toBeUndefined();
    });
  });

  it('wakes only squads that hired a coach, and keeps their memory for the next one', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      const by = MemberId.parse(mia);
      const hiring = createCoachHiring({
        hiring: createPostgresCoachHiring(trx),
        catalog: createPostgresCoachCatalog(trx),
      });
      const { agent, runs } = scriptedAgent(() => [
        { tool: 'edit_file', input: { path: 'memory.md', find: '', replace: '队名：squad' } },
      ]);
      await wakes(fixture, { agent }).run();
      expect(await hiring.fire({ squad, by })).toStrictEqual({ fired: 'xiaohun' });

      // Fired: the next day comes and no coach wakes.
      const tomorrow = new Date(now.getTime() + 86_400_000);
      expect(await wakes(fixture, { agent, at: tomorrow }).run()).toMatchObject({
        squads: 0,
        queued: 0,
      });
      expect(runs).toHaveLength(2);
      await expect(hiring.fire({ squad, by })).rejects.toBeInstanceOf(NoCoachHiredError);

      // A retired coach can't be hired; 小混 again can, and reads the squad's memory.
      await expect(
        hiring.hire({ squad, coach: CoachId.parse('nobody'), by }),
      ).rejects.toBeInstanceOf(CoachNotOfferedError);
      await hiring.hire({ squad, coach: CoachId.parse('xiaohun'), by });
      await expect(
        hiring.hire({ squad, coach: CoachId.parse('xiaohun'), by }),
      ).rejects.toBeInstanceOf(CoachAlreadyHiredError);
      await wakes(fixture, { agent, at: tomorrow }).run();
      // Both earlier wakes added a line; the new hire dreams over yesterday with them, then wakes
      // for the day.
      expect(runs[2]?.task).toContain('夜里，整理你的记性。');
      expect(runs[2]?.task).toContain('【memory.md】\n队名：squad\n队名：squad');

      const report = await createPostgresCoachReport(trx).squad(squad, tomorrow);
      expect(report).toMatchObject({
        coach: 'xiaohun',
        files: [
          { path: 'memory.md', body: '队名：squad\n队名：squad\n队名：squad\n队名：squad' },
          // Started once, on the first wake.
          { path: 'squad.md' },
        ],
        usage: {
          total: {
            wakes: 4,
            requests: 8,
            inputTokens: 48_000,
            cachedInputTokens: 0,
            outputTokens: 3_200,
            costMicros: 18_400,
          },
        },
      });
      const hires = await sql<{ kind: string }>`
        select kind from public.squad_coach_events where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(hires.rows.map(({ kind }) => kind)).toStrictEqual(['hired', 'fired', 'hired']);
    });
  });

  it('knows a coach hired back until it first runs for the squad', async () => {
    await rolledBack(async ({ trx, squad, mia }) => {
      const by = MemberId.parse(mia);
      const catalog = createPostgresCoachCatalog(trx);
      const store = createPostgresCoachHiring(trx);
      const hiring = createCoachHiring({ hiring: store, catalog });
      const xiaohun = CoachId.parse('xiaohun');
      const nuannuan = CoachId.parse('nuannuan');
      const [first] = await catalog.list();
      if (first === undefined) throw new Error('No coach.');
      await catalog.save({ ...first, id: nuannuan, name: '暖暖' }, by);

      // Its first coach is new to the squad, and so is the next.
      expect(await store.backAgain(squad)).toBe(false);
      await hiring.change({ squad, coach: nuannuan, by });
      expect(await store.backAgain(squad)).toBe(false);
      // The first one hired again is back.
      await hiring.change({ squad, coach: xiaohun, by });
      expect(await store.backAgain(squad)).toBe(true);
      // A wake finished without running (its check-in no longer shared with AI) tells it nothing.
      await sql`
        insert into public.coach_wakes (squad_id, reason, day, state, claimed_at)
        values (${squad}, 'daily', '2026-11-08', 'done', now())`.execute(trx);
      expect(await store.backAgain(squad)).toBe(true);
      // Once it has run for the squad, it is just its coach again.
      await sql`
        insert into public.coach_usage
          (squad_id, coach_id, model, requests, input_tokens, output_tokens, cost_micros)
        values (${squad}, 'xiaohun', 'gpt-test', 1, 10, 10, 1)`.execute(trx);
      expect(await store.backAgain(squad)).toBe(false);
      // No coach, nothing to be back.
      await hiring.fire({ squad, by });
      expect(await store.backAgain(squad)).toBe(false);
    });
  });

  it('changes the coach in one step for 换教练, and says when it already had it', async () => {
    await rolledBack(async ({ trx, squad, mia }) => {
      const by = MemberId.parse(mia);
      const catalog = createPostgresCoachCatalog(trx);
      const hiring = createCoachHiring({ hiring: createPostgresCoachHiring(trx), catalog });
      const xiaohun = CoachId.parse('xiaohun');
      const nuannuan = CoachId.parse('nuannuan');
      const [first] = await catalog.list();
      if (first === undefined) throw new Error('No coach.');
      await catalog.save({ ...first, id: nuannuan, name: '暖暖' }, by);

      expect((await hiring.offered()).map(({ id }) => id)).toStrictEqual([nuannuan, xiaohun]);
      expect(await hiring.current(squad)).toMatchObject({ coach: { id: xiaohun } });
      expect(await hiring.change({ squad, coach: xiaohun, by })).toMatchObject({
        coach: { id: xiaohun },
        changed: false,
      });
      expect(await hiring.change({ squad, coach: nuannuan, by })).toMatchObject({
        coach: { id: nuannuan, name: '暖暖' },
        changed: true,
      });
      expect(await hiring.current(squad)).toMatchObject({ coach: { id: nuannuan } });

      // A retired coach can't be hired; the squad keeps the one it has.
      await catalog.save({ ...first, offered: false }, by);
      await expect(hiring.change({ squad, coach: xiaohun, by })).rejects.toBeInstanceOf(
        CoachNotOfferedError,
      );
      expect((await hiring.offered()).map(({ id }) => id)).toStrictEqual([nuannuan]);
      // Retired since it was hired, the squad's own coach is still a retry, never a refusal.
      const hiredNow = (await catalog.list()).find(({ id }) => id === nuannuan);
      if (hiredNow === undefined) throw new Error('No 暖暖.');
      await catalog.save({ ...hiredNow, offered: false }, by);
      expect(await hiring.change({ squad, coach: nuannuan, by })).toMatchObject({
        coach: { id: nuannuan },
        changed: false,
      });

      // A squad that isn't there is refused before anything is written, so the transaction
      // it ran in goes on.
      await catalog.save(hiredNow, by);
      await expect(
        hiring.change({ squad: SquadId.parse(randomUUID()), coach: nuannuan, by }),
      ).rejects.toBeInstanceOf(CoachSquadNotFoundError);
      expect(await hiring.current(squad)).toMatchObject({ coach: { id: nuannuan } });

      // The fixture's hire, then the change: fired and hired in order, each by the member.
      const events = await sql<{ kind: string; coach_id: string; changed_by: string }>`
        select kind, coach_id, changed_by from public.squad_coach_events
        where squad_id = ${squad} order by id`.execute(trx);
      expect(events.rows).toStrictEqual([
        { kind: 'hired', coach_id: 'xiaohun', changed_by: mia },
        { kind: 'fired', coach_id: 'xiaohun', changed_by: mia },
        { kind: 'hired', coach_id: 'nuannuan', changed_by: mia },
      ]);

      await hiring.fire({ squad, by });
      expect(await hiring.current(squad)).toBeUndefined();
    });
  });

  it('answers an @ of it at once, even where it said nothing yet, and the job catches a missed one', async () => {
    await rolledBack(async (fixture) => {
      const { squad, leo, checkIn } = fixture;
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('要回的这句') ? [{ tool: 'answer', input: { text: '下雨就练核心' } }] : [],
      );
      const told: Parameters<CoachAnswered>[0][] = [];
      const answered: CoachAnswered = (answer) => {
        told.push(answer);
        return Promise.resolve();
      };
      const asked = await commentOn(fixture, {
        member: leo,
        text: '@小混 下雨还练吗',
        at: new Date(now.getTime() + 60_000),
        mentionsCoach: 'xiaohun',
      });
      const withAsk: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, comments: [asked] })),
      };
      const coach = wakes(
        { ...fixture, week: withAsk },
        { agent, answered, at: new Date(now.getTime() + 2 * 60_000) },
      );
      // Not in a squad that isn't the post's, nor for another coach.
      await coach.answer({ checkIn, comment: asked.id, coach: 'xiaohun', squads: [] });
      await coach.answer({ checkIn, comment: asked.id, coach: 'maotou', squads: [squad] });
      expect(runs).toHaveLength(0);
      await coach.answer({ checkIn, comment: asked.id, coach: 'xiaohun', squads: [squad] });
      const answering = runs.find(({ task }) => task.includes('要回的这句'));
      expect(answering?.task).toContain('有人在评论里 @ 你。');
      expect(answering?.task).toContain(
        '你们在下面的对话：\n- 队员2：「@小混 下雨还练吗」（要回的这句）',
      );
      expect(told).toStrictEqual([
        {
          squad,
          checkIn,
          comment: asked.id,
          commenter: leo,
          coach: 'xiaohun',
          text: '下雨就练核心',
          mentions: [],
        },
      ]);
    });
  });

  it('answers each reply to it at once, with the talk so far, and tells who wrote it', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, leo, checkIn } = fixture;
      const { agent, runs } = scriptedAgent((task) => {
        if (task.includes('有人打卡')) return [{ tool: 'reply', input: { text: '周日也跑？' } }];
        if (task.includes('要回的这句')) {
          return [
            { tool: 'react', input: { emoji: '🔥' } },
            { tool: 'answer', input: { text: '队员2 你也来' } },
            { tool: 'answer', input: { text: task.includes('你喊') ? '喊破嗓子' : '你也来跑' } },
          ];
        }
        return [];
      });
      const told: Parameters<CoachAnswered>[0][] = [];
      const answered: CoachAnswered = (answer) => {
        told.push(answer);
        return Promise.resolve();
      };
      // Nothing to reply to before the coach says anything.
      const early = await commentOn(fixture, {
        member: leo,
        text: '教练在吗',
        at: new Date(now.getTime() - 5 * 60_000),
        toCoach: 'xiaohun',
      });
      const before: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, comments: [early] })),
      };
      await wakes({ ...fixture, week: before }, { agent, answered }).answer({
        checkIn,
        comment: early.id,
        coach: 'xiaohun',
        squads: [fixture.squad],
      });
      expect(runs).toHaveLength(0);
      await sql`delete from public.check_in_comments where id = ${early.id}`.execute(trx);

      await wakes(fixture, { agent }).run();
      const first = await commentOn(fixture, {
        member: leo,
        text: '你也跑吗',
        at: new Date(now.getTime() + 60_000),
        toCoach: 'xiaohun',
      });
      const later = new Date(now.getTime() + 2 * 60_000);
      const withFirst: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, comments: [first] })),
      };
      await wakes({ ...fixture, week: withFirst }, { agent, answered, at: later }).answer({
        checkIn,
        comment: first.id,
        coach: 'xiaohun',
        squads: [fixture.squad],
      });
      // Another coach, or one the squad didn't hire, has nothing to answer.
      await wakes({ ...fixture, week: withFirst }, { agent, answered, at: later }).answer({
        checkIn,
        comment: first.id,
        coach: 'maotou',
        squads: [fixture.squad],
      });
      // Nor one in a squad the writer isn't in, which shares the check-in with theirs.
      const ran = runs.length;
      const outside = await commentOn(fixture, {
        member: leo,
        text: '我在别的队',
        at: new Date(now.getTime() + 150_000),
        toCoach: 'xiaohun',
      });
      const withoutLeo: SquadWeek = {
        ...withFirst,
        members: withFirst.members.filter(({ member }) => member !== leo),
        checkIns: withFirst.checkIns.map((each) => ({ ...each, comments: [first, outside] })),
      };
      await wakes({ ...fixture, week: withoutLeo }, { agent, answered, at: later }).answer({
        checkIn,
        comment: outside.id,
        coach: 'xiaohun',
        squads: [fixture.squad],
      });
      expect(runs).toHaveLength(ran);
      await sql`delete from public.check_in_comments where id = ${outside.id}`.execute(trx);
      const second = await commentOn(fixture, {
        member: mia,
        text: '那你喊大声点',
        at: new Date(now.getTime() + 3 * 60_000),
        toCoach: 'xiaohun',
      });
      const withBoth: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, comments: [first, second] })),
      };
      const coach = wakes(
        { ...fixture, week: withBoth },
        { agent, answered, at: new Date(now.getTime() + 4 * 60_000) },
      );
      await coach.answer({ checkIn, comment: second.id, coach: 'xiaohun', squads: [squad] });
      // Answered once: the next run, or the same reply again, finds it answered.
      await coach.answer({ checkIn, comment: second.id, coach: 'xiaohun', squads: [squad] });
      await coach.run();

      // The check-in's wake, the day's, then one for each reply.
      expect(runs.map(({ tools }) => tools.at(-1))).toStrictEqual([
        'react',
        'note_to',
        'answer',
        'answer',
      ]);
      expect(runs[2]?.task).toContain('- 你：「周日也跑？」\n- 队员2：「你也跑吗」（要回的这句）');
      expect(runs[3]?.task).toContain(
        '- 你：「周日也跑？」\n- 队员2：「你也跑吗」\n- 你：「你也来跑」\n- 队员1：「那你喊大声点」（要回的这句）',
      );
      // Only `answer` on a reply's wake; it may not name 队员N, as any line members read.
      expect(runs[2]?.answers).toStrictEqual([
        'no tool react',
        '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。',
        '已回复。',
      ]);
      expect(told).toStrictEqual([
        {
          squad,
          checkIn,
          comment: first.id,
          commenter: leo,
          coach: 'xiaohun',
          text: '你也来跑',
          mentions: [],
        },
        {
          squad,
          checkIn,
          comment: second.id,
          commenter: mia,
          coach: 'xiaohun',
          text: '喊破嗓子',
          mentions: [],
        },
      ]);
      // The next day's wake goes over the last day's talk, to remember what it missed.
      await wakes(
        { ...fixture, week: withBoth },
        { agent, at: new Date(now.getTime() + 20 * 3_600_000) },
      ).run();
      expect(runs.at(-1)?.task).toContain(
        '过去一天打卡下面的对话（先后顺序）：\n- 11-01 周日 队员1 训练 跑步',
      );
      expect(runs.at(-1)?.task).toContain(
        '  你：「周日也跑？」\n  队员2：「你也跑吗」\n  你：「你也来跑」\n  队员1：「那你喊大声点」\n  你：「喊破嗓子」',
      );
      const activity = await createCoachActivity({
        store: createPostgresCoachActivity(trx),
      }).squad({ squad, checkIns: [checkIn] });
      expect(
        activity.answers.map(({ comment, text, coach: { id } }) => ({ comment, text, id })),
      ).toStrictEqual([
        { comment: first.id, text: '你也来跑', id: 'xiaohun' },
        { comment: second.id, text: '喊破嗓子', id: 'xiaohun' },
      ]);
      // Members may reply only to a coach that wrote a line here.
      const spoke = createCoachActivity({ store: createPostgresCoachActivity(trx) });
      expect(await spoke.spoke({ squads: [squad], checkIn, coach: 'xiaohun' })).toBe(true);
      expect(await spoke.spoke({ squads: [squad], checkIn, coach: 'maotou' })).toBe(false);
      expect(await spoke.spoke({ squads: [], checkIn, coach: 'xiaohun' })).toBe(false);

      // An answer goes with the reply it answers, and is never changed.
      await sql`savepoint attempt`.execute(trx);
      await expect(
        sql`update public.coach_answers set text = '改了' where comment_id = ${first.id}`.execute(
          trx,
        ),
      ).rejects.toThrow('coach_answers is append-only');
      await sql`rollback to savepoint attempt`.execute(trx);
      await sql`delete from public.check_in_comments where id = ${first.id}`.execute(trx);
      const left = await sql<{ comment_id: string }>`
        select comment_id from public.coach_answers where squad_id = ${squad}`.execute(trx);
      expect(left.rows).toStrictEqual([{ comment_id: second.id }]);
    });
  });

  it('saves nothing but the tokens of a failed run, and tries a wake three times', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad } = fixture;
      const { agent, runs } = scriptedAgent(() => 'fail');
      for (const minutes of [0, 10, 20, 30]) {
        await wakes(fixture, { agent, at: new Date(now.getTime() + minutes * 60_000) }).run();
      }
      // Two wakes, three tries each; the fourth run has nothing left to try.
      expect(runs).toHaveLength(6);
      const states = await sql<{
        reason: string;
        state: string;
        tries: number;
        last_error: string;
      }>`
        select reason, state, tries, last_error from public.coach_wakes where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(states.rows).toStrictEqual([
        { reason: 'checkIn', state: 'failed', tries: 3, last_error: 'ModelBehaviorError: no' },
        // Nothing from yesterday to dream over: done without a run.
        { reason: 'dream', state: 'done', tries: 1, last_error: null },
        { reason: 'daily', state: 'failed', tries: 3, last_error: 'ModelBehaviorError: no' },
      ]);
      const counts = await sql<{ files: string; notes: string; usage: string }>`
        select (select count(*) from public.coach_files where squad_id = ${squad}) as files,
          (select count(*) from public.coach_notes where squad_id = ${squad}) as notes,
          (select count(*) from public.coach_usage where squad_id = ${squad}) as usage`.execute(
        trx,
      );
      expect(counts.rows).toStrictEqual([{ files: '0', notes: '0', usage: '6' }]);
    });
  });

  it('is off duty for the rest of the day once the squad spent its cap, and back the next', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      // One wake costs 12,000 input and 800 output tokens: 4,600 micros at the fixture's prices.
      await createCoachSettings({ store: createPostgresCoachSettings(trx) }).change(
        { squadDailyCapMicros: 4_600 },
        MemberId.parse(mia),
      );
      const { agent, runs } = scriptedAgent(() => []);
      expect(await wakes(fixture, { agent }).run()).toMatchObject({ done: 3, failed: 0 });
      expect(runs).toHaveLength(1);
      const tomorrow = new Date(now.getTime() + 86_400_000);
      await wakes(fixture, { agent, at: tomorrow }).run();
      // Back the next day: the night's dream comes first and spends this day's cap.
      expect(runs).toHaveLength(2);
      const states = await sql<{ reason: string; state: string; last_error: string | null }>`
        select reason, state, last_error from public.coach_wakes where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(states.rows).toStrictEqual([
        { reason: 'checkIn', state: 'done', last_error: null },
        {
          reason: 'dream',
          state: 'skipped',
          last_error: 'off duty: the squad spent 4600 of its 4600 micros today',
        },
        {
          reason: 'daily',
          state: 'skipped',
          last_error: 'off duty: the squad spent 4600 of its 4600 micros today',
        },
        { reason: 'dream', state: 'done', last_error: null },
        {
          reason: 'daily',
          state: 'skipped',
          last_error: 'off duty: the squad spent 4600 of its 4600 micros today',
        },
      ]);
    });
  });

  it('is off duty everywhere once every squad together spent the day’s cap', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      const other = SquadId.parse(randomUUID());
      await sql`insert into public.squads (id, name, invite_code) values (${other}, 'other', ${other})`.execute(
        trx,
      );
      // Another squad spent the whole day's cap this morning.
      await sql`insert into public.coach_usage
          (squad_id, coach_id, model, requests, input_tokens, output_tokens, cost_micros, at)
        values (${other}, 'xiaohun', 'openai/gpt-6-luna', 1, 1, 1, 9000, ${new Date(now.getTime() - 3_600_000)})`.execute(
        trx,
      );
      await createCoachSettings({ store: createPostgresCoachSettings(trx) }).change(
        { dailyCapMicros: 9_000 },
        MemberId.parse(mia),
      );
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, { agent }).run();
      expect(runs).toHaveLength(0);
      const states = await sql<{ state: string; last_error: string }>`
        select state, last_error from public.coach_wakes where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(states.rows.map(({ state }) => state)).toStrictEqual([
        'skipped',
        'skipped',
        'skipped',
      ]);
      expect(states.rows[0]?.last_error).toBe(
        'off duty: every squad spent 9000 of the 9000 micros today',
      );
    });
  });

  it('looks at a check-in at once, shows its recent emoji, and keeps every tool call', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, checkIn } = fixture;
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('有人打卡')
          ? [
              { tool: 'squad_week', input: {} },
              { tool: 'react', input: { emoji: '🔥' } },
              { tool: 'reply', input: { text: '队员1 好' } },
              { tool: 'edit_file', input: { path: 'memory.md', find: '', replace: '米亚怕下雨' } },
            ]
          : [],
      );
      const other = SquadId.parse(randomUUID());
      await sql`insert into public.squads (id, name, invite_code) values (${other}, 'other', ${other})`.execute(
        trx,
      );
      // Only the check-in's wake runs, in the squad that hired a coach; the day's waits for the job.
      await wakes(fixture, { agent }).checkedIn({ checkIn, squads: [other, squad] });
      expect(runs).toHaveLength(1);
      expect(runs[0]?.task).toContain('你最近没点过表情。');

      // A second check-in sees the emoji the coach used, newest first.
      const second = randomUUID();
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${second}, ${mia}, '2026-11-01', ${now}, 'healthyMeal', '{"version": 1}')`.execute(
        trx,
      );
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: [
          ...fixture.week.checkIns,
          {
            id: second,
            member: mia,
            day: '2026-11-01',
            createdAt: now,
            kind: 'healthyMeal',
            reactedBy: [],
            comments: [],
          },
        ],
      };
      await wakes({ ...fixture, week }, { agent }).checkedIn({ checkIn: second, squads: [squad] });
      expect(runs).toHaveLength(2);
      expect(runs[1]?.task).toContain('你最近点过的表情（新的在前）：🔥');

      // Each call, with what the tool answered: a read by its length only.
      const weekLength = weekText(fixture.week).length;
      const report = await createPostgresCoachReport(trx).squad(squad, now);
      expect(report.wakes[1]?.steps).toStrictEqual([
        { tool: 'squad_week', input: {}, output: `（${String(weekLength)} 字）` },
        { tool: 'react', input: { emoji: '🔥' }, output: '已点 🔥。' },
        {
          tool: 'reply',
          input: { text: '队员1 好' },
          output: '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。',
        },
        // A file's text by its length: it may be a member's words.
        {
          tool: 'edit_file',
          input: { path: 'memory.md', find: '（0 字）', replace: '（5 字）' },
          output: '已改好，memory.md 现在 5 字。',
        },
      ]);
      expect(JSON.stringify(report.wakes)).not.toContain('跑步');
      expect(JSON.stringify(report.wakes)).not.toContain('怕下雨');
    });
  });

  it('looks at a check-in’s photos only when it asks, once, and keeps only how many', async () => {
    await rolledBack(async (fixture) => {
      const { squad, checkIn } = fixture;
      const asked: (readonly string[])[] = [];
      const photoUrls: CoachPhotoUrls = (paths) => {
        asked.push(paths);
        return Promise.resolve(paths.map((path) => `https://photos.test/${path}`));
      };
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('有人打卡')
          ? [
              { tool: 'look_at_photos', input: {} },
              { tool: 'look_at_photos', input: {} },
              { tool: 'reply', input: { text: '这碗面看着不错' } },
            ]
          : [],
      );
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) =>
          each.id === checkIn ? { ...each, photos: ['m/a.jpg', 'm/b.jpg'] } : each,
        ),
      };
      await wakes({ ...fixture, week }, { agent, photoUrls }).checkedIn({
        checkIn,
        squads: [squad],
      });
      expect(runs[0]?.task).toContain('（2 张照片）');
      expect(runs[0]?.task).not.toContain('m/a.jpg');
      expect(runs[0]?.tools).toContain('look_at_photos');
      expect(runs[0]?.answers).toStrictEqual([
        '这条打卡的 2 张照片，第一张是封面： https://photos.test/m/a.jpg https://photos.test/m/b.jpg',
        '照片你已经看过了，不用再看。',
        '已回复。',
      ]);
      expect(asked).toStrictEqual([['m/a.jpg', 'm/b.jpg']]);
      const report = await createPostgresCoachReport(fixture.trx).squad(squad, now);
      expect(report.wakes[0]?.steps.slice(0, 2)).toStrictEqual([
        { tool: 'look_at_photos', input: {}, output: '（2 张照片）' },
        { tool: 'look_at_photos', input: {}, output: '已经看过了。' },
      ]);
    });
  });

  it('looks up members’ stats and an earlier week only when it asks', async () => {
    await rolledBack(async (fixture) => {
      const { squad, checkIn, mia } = fixture;
      const asked: unknown[] = [];
      const memberFacts: CoachMemberFacts = (input) => {
        asked.push(input);
        return Promise.resolve(
          input.members.map((member) => ({
            member,
            trainedDays: 50,
            healthyMeals: 0,
            cheatMeals: 0,
            disclaimers: 0,
            titles: 0,
            plan: Array.from({ length: 7 }, () => ({ kind: 'rest' as const })),
            fuelGoals: [],
          })),
        );
      };
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('有人打卡')
          ? [
              { tool: 'member_stats', input: {} },
              { tool: 'squad_week', input: { weeks_ago: 1 } },
            ]
          : [],
      );
      const earlier = '2026-10-19';
      await wakes(fixture, {
        agent,
        memberFacts,
        consented: [mia],
        weeks: {
          [fixture.week.weekStart]: fixture.week,
          [earlier]: { weekStart: earlier, members: fixture.week.members, checkIns: [] },
        },
      }).checkedIn({ checkIn, squads: [squad] });
      expect(asked).toStrictEqual([{ members: [mia], weekStart: fixture.week.weekStart }]);
      expect(runs[0]?.answers[0]).toContain('一共练了 50 天');
      expect(runs[0]?.answers[1]).toContain(`本周从 ${earlier}（周一）开始。`);
    });
  });

  it('reads the meme library only when it asks, and keeps the answer by its length', async () => {
    await rolledBack(async (fixture) => {
      const { squad, checkIn } = fixture;
      let reads = 0;
      const memes: CoachMemes = () => {
        reads += 1;
        return Promise.resolve([
          { phrase: '对自己很好', meaning: '照顾自己', background: '小红书上流行' },
        ]);
      };
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('有人打卡') ? [{ tool: 'memes', input: {} }] : [],
      );
      await wakes(fixture, { agent, memes }).checkedIn({ checkIn, squads: [squad] });
      expect(reads).toBe(1);
      expect(runs[0]?.tools).toContain('memes');
      expect(runs[0]?.answers[0]).toBe('- 「对自己很好」：照顾自己（小红书上流行）');
      const report = await createPostgresCoachReport(fixture.trx).squad(squad, now);
      expect(report.wakes[0]?.steps[0]).toStrictEqual({
        tool: 'memes',
        input: {},
        output: '（22 字）',
      });
    });
  });

  it('has no meme tool without the library', async () => {
    await rolledBack(async (fixture) => {
      const { squad, checkIn } = fixture;
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, { agent }).checkedIn({ checkIn, squads: [squad] });
      expect(runs[0]?.tools).not.toContain('memes');
    });
  });

  it('gives the daily wake each member’s day: today’s plan, 饮食小目标 and yesterday’s posts', async () => {
    await rolledBack(async (fixture) => {
      const { mia, leo } = fixture;
      const asked: unknown[] = [];
      const rest = { kind: 'rest' } as const;
      const memberFacts: CoachMemberFacts = (input) => {
        asked.push(input);
        return Promise.resolve([
          {
            member: mia,
            trainedDays: 50,
            healthyMeals: 0,
            cheatMeals: 0,
            disclaimers: 0,
            titles: 0,
            // Sunday, the wake's day, is the last.
            plan: [rest, rest, rest, rest, rest, rest, { kind: 'train', sport: '游泳' }],
            fuelGoals: ['喝够水'],
          },
        ]);
      };
      const { agent, runs } = scriptedAgent(() => []);
      const saturday = {
        id: randomUUID(),
        member: leo,
        day: '2026-10-31',
        createdAt: new Date('2026-10-31T20:00:00Z'),
        kind: 'healthyMeal' as const,
        text: '自己做的',
        postedTime: '22:05',
        reactedBy: [mia],
        comments: [],
      };
      await wakes(fixture, {
        agent,
        memberFacts,
        weeks: {
          [fixture.week.weekStart]: {
            ...fixture.week,
            checkIns: [saturday, ...fixture.week.checkIns],
          },
        },
      }).run();
      const daily = runs.find(({ task }) => task.includes('新的一天'));
      // Asked once, by the server, for everyone it writes to.
      expect(asked[0]).toStrictEqual({ members: [mia, leo], weekStart: fixture.week.weekStart });
      expect(daily?.task).toContain('新的一天：2026-11-01，周日。');
      expect(daily?.task).toContain(
        '- 队员1：今天出赛表排了游泳；这周的饮食小目标：喝够水；这周已经练了 1 天。',
      );
      // A member whose plan it couldn't read still gets a note.
      expect(daily?.task).toContain('- 队员2：这周已经练了 0 天。');
      expect(daily?.task).toContain(
        '昨天（周六）小队的动态：\n- 10-31 周六 队员2 健康餐 （本人当地 22:05 发） 「自己做的」 · 点了表情：队员1',
      );
    });
  });

  it('tells the daily wake each member’s weather, and writes the notes without it when it fails', async () => {
    await rolledBack(async (fixture) => {
      const { mia, leo } = fixture;
      const asked: unknown[] = [];
      const weatherOf: CoachWeather = (input) => {
        asked.push(input);
        // Only 队员1 shared where they are.
        return Promise.resolve(new Map([[mia, '今天雨，8–13°C，降水概率 80%']]));
      };
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, { agent, weatherOf }).run();
      const daily = runs.find(({ task }) => task.includes('新的一天'));
      expect(asked).toStrictEqual([{ members: [mia, leo], day: '2026-11-01' }]);
      expect(daily?.task).toContain(
        '- 队员1：这周已经练了 1 天；当地今天雨，8–13°C，降水概率 80%。',
      );
      expect(daily?.task).toContain('- 队员2：这周已经练了 0 天。');
    });
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, {
        agent,
        weatherOf: () => Promise.reject(new Error('no weather')),
      }).run();
      expect(runs.find(({ task }) => task.includes('新的一天'))?.task).toContain(
        '- 队员1：这周已经练了 1 天。',
      );
    });
  });

  it('sets a day’s challenge on a note, gives a gift, and tells a check-in’s wake the answer', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, leo } = fixture;
      const given: unknown[] = [];
      const gifting: CoachGifting = {
        // 队员2 got one this week already; 队员1 has the cap.
        options: ({ members }) =>
          Promise.resolve({
            pool: [{ id: 'gift-scarf', description: '红围巾' }, { id: 'gift-cap' }],
            open: new Map(
              members.filter((each) => each === mia).map((each) => [each, ['gift-cap']]),
            ),
          }),
        give: (input) => {
          given.push(input);
          return Promise.resolve(undefined);
        },
      };
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('新的一天')
          ? [
              {
                tool: 'note_to',
                input: {
                  member: '队员1',
                  text: '今天多喝水',
                  challenge: { title: '喝水', amount: 8, line: '天干，别等口渴' },
                },
              },
              {
                tool: 'note_to',
                input: {
                  member: '队员1',
                  text: '今天多喝水',
                  challenge: { title: '喝水', amount: 8, unit: '杯', line: '天干，别等口渴' },
                },
              },
              // A rest day's blank challenge, as the model sends it, is none.
              {
                tool: 'note_to',
                input: {
                  member: '队员2',
                  text: '今天走走',
                  challenge: { title: ' ', amount: 0, unit: '', line: '' },
                },
              },
              { tool: 'give_gift', input: { member: '队员2', piece: 'gift-scarf', line: '冷' } },
              { tool: 'give_gift', input: { member: '队员1', piece: 'gift-cap', line: '戴上' } },
              { tool: 'give_gift', input: { member: '队员1', piece: 'gift-hat', line: '戴上' } },
              {
                tool: 'give_gift',
                input: { member: '队员1', piece: 'gift-scarf', line: '天冷了' },
              },
            ]
          : task.includes('你今天给他的挑战')
            ? [{ tool: 'complete_challenge', input: {} }]
            : [],
      );
      await wakes(fixture, { agent, gifting }).run();
      const daily = runs.find(({ task }) => task.includes('新的一天'));
      expect(daily?.tools).toContain('give_gift');
      expect(daily?.task).toContain('礼物清单：\n- gift-scarf：红围巾\n- gift-cap');
      expect(daily?.task).toContain('这周还能收礼物的：\n- 队员1（已有：gift-cap）');
      expect(daily?.answers.slice(0, 7)).toStrictEqual([
        '挑战不对：title 不超过 8 字；amount 是 1 到 9999 的整数，unit 不超过 4 字，两个一起填或都不填；line 不超过 24 字。',
        '便条写好了，给 队员1，挑战「喝水 8 杯」。',
        '便条写好了，给 队员2。',
        '队员2 这周不能收礼物；能收的是：队员1。',
        '队员1 已经有 gift-cap 了，换一件。',
        '没有 gift-hat 这件；能送的见任务里的礼物清单。',
        'gift-scarf 送给 队员1 了。',
      ]);
      expect(given).toStrictEqual([
        { squad, member: mia, coach: 'xiaohun', piece: 'gift-scarf', line: '天冷了' },
      ]);
      const notes = await sql<{ member_id: string; challenge_title: string | null }>`
        select member_id, challenge_title, challenge_amount, challenge_unit, challenge_line
        from public.coach_member_notes where squad_id = ${squad} order by member_id = ${mia} desc
      `.execute(trx);
      expect(notes.rows).toStrictEqual([
        {
          member_id: mia,
          challenge_title: '喝水',
          challenge_amount: 8,
          challenge_unit: '杯',
          challenge_line: '天干，别等口渴',
        },
        {
          member_id: leo,
          challenge_title: null,
          challenge_amount: null,
          challenge_unit: null,
          challenge_line: null,
        },
      ]);

      // The member accepts it (the first answer stands), and the next check-in's wake knows.
      const activity = createCoachActivity({ store: createPostgresCoachActivity(trx) });
      const [mine, theirs] = await sql<{ id: string }>`
        select id from public.coach_member_notes where squad_id = ${squad} order by member_id = ${mia} desc
      `
        .execute(trx)
        .then(({ rows }) => rows.map(({ id }) => Number(id)));
      // Answered only once the note reached them.
      const early = (note: number | undefined) =>
        activity.answerChallenge({ squad, member: mia, note: note ?? 0, answer: 'accepted' });
      await expect(early(mine)).rejects.toThrow(CoachNoteNotFoundError);
      await sql`insert into public.coach_member_note_deliveries (note_id)
        select id from public.coach_member_notes where squad_id = ${squad}`.execute(trx);
      const answer = (
        member: string,
        { note, said }: { note: number | undefined; said: 'accepted' | 'declined' },
      ) => activity.answerChallenge({ squad, member, note: note ?? 0, answer: said });
      expect(await answer(mia, { note: mine, said: 'accepted' })).toStrictEqual({
        answer: 'accepted',
      });
      expect(await answer(mia, { note: mine, said: 'declined' })).toStrictEqual({
        answer: 'accepted',
      });
      await expect(answer(leo, { note: mine, said: 'accepted' })).rejects.toThrow(
        CoachNoteNotFoundError,
      );
      await expect(answer(leo, { note: theirs, said: 'accepted' })).rejects.toThrow(
        CoachNoteNoChallengeError,
      );
      const later = randomUUID();
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${later}, ${mia}, '2026-11-01', ${now}, 'healthyMeal', '{"version": 1}')`.execute(
        trx,
      );
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: [
          ...fixture.week.checkIns,
          {
            id: later,
            member: mia,
            day: '2026-11-01',
            createdAt: now,
            kind: 'healthyMeal',
            reactedBy: [],
            comments: [],
          },
        ],
      };
      await wakes({ ...fixture, week }, { agent }).checkedIn({ checkIn: later, squads: [squad] });
      expect(runs.at(-1)?.task).toContain('你今天给他的挑战：「喝水 8 杯」，他接受了。');
      // The coach saw it done in the check-in and marked it, once.
      expect(runs.at(-1)?.tools).toContain('complete_challenge');
      expect(runs.at(-1)?.answers).toStrictEqual(['已记他完成。']);
      const done = await sql<{ note_id: string; by: string }>`
        select note_id, by from public.coach_challenge_completions
        where note_id in (${String(mine)}, ${String(theirs)})`.execute(trx);
      expect(done.rows).toStrictEqual([{ note_id: String(mine), by: 'coach' }]);
      // The next check-in's wake knows, with nothing left to mark.
      const again = randomUUID();
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${again}, ${mia}, '2026-11-01', ${now}, 'healthyMeal', '{"version": 1}')`.execute(
        trx,
      );
      await wakes(
        {
          ...fixture,
          week: {
            ...week,
            checkIns: [
              ...week.checkIns,
              {
                id: again,
                member: mia,
                day: '2026-11-01',
                createdAt: now,
                kind: 'healthyMeal',
                reactedBy: [],
                comments: [],
              },
            ],
          },
        },
        { agent },
      ).checkedIn({ checkIn: again, squads: [squad] });
      expect(runs.at(-1)?.task).toContain('你今天给他的挑战：「喝水 8 杯」，你已经记他完成了。');
      expect(runs.at(-1)?.tools).not.toContain('complete_challenge');
    });
  });

  it('reads yesterday from last week on a Monday, with only consented members’ posts', async () => {
    await rolledBack(async (fixture) => {
      const { mia, leo } = fixture;
      const { agent, runs } = scriptedAgent(() => []);
      const sunday = (member: string, text: string) => ({
        id: randomUUID(),
        member,
        day: '2026-11-01',
        createdAt: new Date('2026-11-01T20:00:00Z'),
        kind: 'healthyMeal' as const,
        text,
        reactedBy: [],
        comments: [],
      });
      // 10:00 in New York on Monday 2026-11-02, past the daily wake's hour.
      await wakes(fixture, {
        agent,
        at: new Date('2026-11-02T15:00:00Z'),
        consented: [mia],
        weeks: {
          '2026-10-26': {
            ...fixture.week,
            checkIns: [sunday(mia, '米亚的饭'), sunday(leo, '没同意的人')],
          },
          '2026-11-02': { weekStart: '2026-11-02', members: fixture.week.members, checkIns: [] },
        },
      }).run();
      const daily = runs.find(({ task }) => task.includes('新的一天：2026-11-02'));
      expect(daily?.task).toContain(
        '昨天（周日）小队的动态：\n- 11-01 周日 队员1 健康餐 「米亚的饭」',
      );
      expect(daily?.task).not.toContain('没同意的人');
      // Only the consented member gets a note.
      expect(daily?.task).toContain('今天给这些人各写一张便条：\n- 队员1：这周已经练了 0 天。');
      expect(daily?.task).not.toContain('- 队员2：');
    });
  });

  it('tells an @ about a post with photos that it hasn’t seen them, only when it can look', async () => {
    await rolledBack(async (fixture) => {
      const { squad, leo, checkIn } = fixture;
      const asked = await commentOn(fixture, {
        member: leo,
        text: '@小混 你看看我们吃了啥',
        at: new Date(now.getTime() + 60_000),
        mentionsCoach: 'xiaohun',
      });
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) =>
          each.id === checkIn
            ? { ...each, photos: ['m/a.jpg', 'm/b.jpg'], comments: [asked] }
            : each,
        ),
      };
      const hint =
        '这条打卡有 2 张照片，你还没看过。要回的这句问到照片里的东西，就先用 look_at_photos 看。';
      const seeing = scriptedAgent(() => []);
      await wakes(
        { ...fixture, week },
        {
          agent: seeing.agent,
          photoUrls: (paths) => Promise.resolve(paths.map((path) => `https://photos.test/${path}`)),
          at: new Date(now.getTime() + 2 * 60_000),
        },
      ).answer({ checkIn, comment: asked.id, coach: 'xiaohun', squads: [squad] });
      expect(seeing.runs[0]?.task).toContain(hint);
      expect(seeing.runs[0]?.tools).toContain('look_at_photos');
    });
    await rolledBack(async (fixture) => {
      const { squad, leo, checkIn } = fixture;
      const asked = await commentOn(fixture, {
        member: leo,
        text: '@小混 你看看我们吃了啥',
        at: new Date(now.getTime() + 60_000),
        mentionsCoach: 'xiaohun',
      });
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) =>
          each.id === checkIn ? { ...each, photos: ['m/a.jpg'], comments: [asked] } : each,
        ),
      };
      // Without photo URLs it can't look, so it isn't told to.
      const blind = scriptedAgent(() => []);
      await wakes(
        { ...fixture, week },
        { agent: blind.agent, at: new Date(now.getTime() + 2 * 60_000) },
      ).answer({ checkIn, comment: asked.id, coach: 'xiaohun', squads: [squad] });
      expect(blind.runs[0]?.task).toContain('有人在评论里 @ 你。');
      expect(blind.runs[0]?.task).not.toContain('look_at_photos');
      expect(blind.runs[0]?.tools).not.toContain('look_at_photos');
    });
  });

  it('has no photo tool for a check-in without photos', async () => {
    await rolledBack(async (fixture) => {
      const { squad, checkIn } = fixture;
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, {
        agent,
        photoUrls: () => Promise.reject(new Error('never asked')),
      }).checkedIn({ checkIn, squads: [squad] });
      expect(runs[0]?.tools).not.toContain('look_at_photos');
    });
  });

  it('does not look at a check-in while coaching is off', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => []);
      await createCoachSettings({ store: createPostgresCoachSettings(fixture.trx) }).change(
        { coaching: false },
        MemberId.parse(fixture.mia),
      );
      await wakes(fixture, { agent }).checkedIn({
        checkIn: fixture.checkIn,
        squads: [fixture.squad],
      });
      expect(runs).toHaveLength(0);
    });
  });

  it('@s any teammate in a reply, by nickname, and tells the server whom', async () => {
    await rolledBack(async (fixture) => {
      const { leo } = fixture;
      const week: SquadWeek = {
        ...fixture.week,
        members: [
          fixture.week.members[0] ?? { member: fixture.mia },
          { member: leo, nickname: '小乐' },
        ],
      };
      const { agent, runs } = scriptedAgent((task) =>
        task.startsWith('有人打卡')
          ? [
              { tool: 'reply', input: { text: '一起跑', at: ['队员3'] } },
              // The post's author gets the reply anyway: never @'d.
              { tool: 'reply', input: { text: '一起跑', at: ['队员1', '队员2'] } },
            ]
          : [],
      );
      const told: Parameters<CoachReplied>[0][] = [];
      await wakes(
        { ...fixture, week },
        {
          agent,
          replied: (reply) => {
            told.push(reply);
            return Promise.resolve();
          },
        },
      ).run();
      expect(runs[0]?.answers).toStrictEqual([
        '不能 @ 队员3；能 @ 的是：队员1、队员2。',
        '已回复。',
      ]);
      expect(told).toMatchObject([{ author: fixture.mia, text: '@小乐 一起跑', mentions: [leo] }]);
      // Kept with the line, so the app can show the @ as a tag that opens 小乐's card.
      const checkIn = told[0]?.checkIn ?? '';
      const read = await createPostgresCoachActivity(fixture.trx).replies(fixture.squad, [checkIn]);
      expect(read).toMatchObject([{ checkIn, text: '@小乐 一起跑', mentions: [leo] }]);
    });
  });

  it('dreams at night over yesterday: rewrites whole files, and only then', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, leo } = fixture;
      const { agent, runs } = scriptedAgent((task) =>
        task.startsWith('夜里')
          ? [
              { tool: 'rewrite_file', input: { path: 'notes.md', body: '不存在' } },
              { tool: 'rewrite_file', input: { path: 'memory.md', body: ' 队员2 周末爱跑步 \n' } },
              { tool: 'rewrite_file', input: { path: 'squad.md', body: '队名：squad' } },
            ]
          : [],
      );
      // Today: nothing from yesterday, so the night costs nothing.
      await wakes(fixture, { agent }).run();
      expect(runs.map(({ task }) => task.slice(0, 4))).toStrictEqual(['有人打卡', '新的一天']);
      expect(runs[0]?.tools).not.toContain('rewrite_file');

      const tomorrow = new Date(now.getTime() + 86_400_000);
      await wakes(fixture, { agent, at: tomorrow }).run();
      const dream = runs[2];
      expect(dream?.task).toContain('昨天（周日）小队的动态：');
      expect(dream?.task).toContain('前后矛盾的，留最新的。');
      expect(dream?.tools).toContain('rewrite_file');
      expect(dream?.tools).not.toContain('post_note');
      expect(dream?.tools).not.toContain('reply');
      expect(dream?.answers).toStrictEqual([
        '没有 notes.md 这个文件；能用的文件见任务里的列表。',
        '已重写 memory.md，现在 9 字。',
        '已重写 squad.md，现在 8 字。',
      ]);
      // The day's wake reads what the night left.
      expect(runs[3]?.task).toContain('【memory.md】\n队员2 周末爱跑步');
      const files = await sql<{ path: string; body: string }>`
        select distinct on (path) path, body from public.coach_files
        where squad_id = ${squad} order by path, id desc`.execute(trx);
      expect(files.rows).toStrictEqual([
        { path: 'memory.md', body: `{队员:${leo}} 周末爱跑步` },
        { path: 'squad.md', body: '队名：squad' },
      ]);
      const reasons = await sql<{ reason: string; state: string }>`
        select reason, state from public.coach_wakes where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(reasons.rows).toStrictEqual([
        { reason: 'checkIn', state: 'done' },
        { reason: 'dream', state: 'done' },
        { reason: 'daily', state: 'done' },
        { reason: 'dream', state: 'done' },
        { reason: 'daily', state: 'done' },
      ]);
    });
  });

  it('tells the night how yesterday’s challenges went, and why one was let go', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, leo } = fixture;
      const { agent, runs } = scriptedAgent(() => []);
      const noted = await sql<{ id: string; member_id: string }>`
        insert into public.coach_member_notes
          (squad_id, member_id, coach_id, day, text, challenge_title, challenge_amount, challenge_unit)
        values (${squad}, ${mia}, 'xiaohun', '2026-11-01', '多喝水', '喝水', 8, '杯'),
          (${squad}, ${leo}, 'xiaohun', '2026-11-01', '早餐加个蛋', '吃鸡蛋', null, null)
        returning id, member_id`.execute(trx);
      const noteOf = (member: string) =>
        noted.rows.find((row) => row.member_id === member)?.id ?? '';
      await sql`insert into public.coach_member_note_deliveries (note_id)
        select id from public.coach_member_notes where squad_id = ${squad}`.execute(trx);
      const activity = createCoachActivity({ store: createPostgresCoachActivity(trx) });
      await activity.answerChallenge({
        squad,
        member: leo,
        note: Number(noteOf(leo)),
        answer: 'declined',
        reason: '我鸡蛋过敏',
      });
      // A check-in's wake that day is told why it was let go, and not to repeat it.
      const meal = randomUUID();
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${meal}, ${leo}, '2026-11-01', ${now}, 'healthyMeal', '{"version": 1}')`.execute(
        trx,
      );
      await wakes(
        {
          ...fixture,
          week: {
            ...fixture.week,
            checkIns: [
              ...fixture.week.checkIns,
              {
                id: meal,
                member: leo,
                day: '2026-11-01',
                createdAt: now,
                kind: 'healthyMeal',
                reactedBy: [],
                comments: [],
              },
            ],
          },
        },
        { agent },
      ).checkedIn({ checkIn: meal, squads: [squad] });
      expect(runs.at(-1)?.task).toContain(
        '你今天给他的挑战：「吃鸡蛋」，他说算了，因为「我鸡蛋过敏」（他只告诉了你，别在回复里说）。',
      );
      expect(runs.at(-1)?.tools).not.toContain('complete_challenge');
      // The coach can't mark one let go, or one of another day.
      const notes = createPostgresCoachStores(trx).memberNotes;
      const coachDone = (member: string, day: string) =>
        notes.complete({ note: Number(noteOf(member)), by: 'coach', day });
      expect(await coachDone(leo, '2026-11-01')).toBe(false);
      expect(await coachDone(mia, '2026-11-02')).toBe(false);
      await sql`insert into public.coach_challenge_completions (note_id, by)
        values (${noteOf(mia)}, 'member')`.execute(trx);
      await wakes(fixture, { agent, at: new Date(now.getTime() + 86_400_000) }).run();
      const dream = runs.find(({ task }) => task.startsWith('夜里'));
      expect(dream?.task).toContain(
        '昨天的挑战：\n- 队员1「喝水 8 杯」：完成了\n- 队员2「吃鸡蛋」：没接，因为「我鸡蛋过敏」（他只告诉了你）',
      );
    });
  });

  it('saves no new version of a file an edit left as it was', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad } = fixture;
      const { agent, runs } = scriptedAgent(() => [
        { tool: 'edit_file', input: { path: 'memory.md', find: '', replace: '跑' } },
        { tool: 'edit_file', input: { path: 'memory.md', find: '跑', replace: '' } },
      ]);
      expect(await wakes(fixture, { agent }).run()).toMatchObject({ done: 3 });
      expect(runs).toHaveLength(2);
      // Only the squad's file, started on the first wake.
      const files = await sql<{ path: string }>`
        select path from public.coach_files where squad_id = ${squad}`.execute(trx);
      expect(files.rows).toStrictEqual([{ path: 'squad.md' }]);
    });
  });

  it('sends the model only the words of members who agreed to AI use', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => [{ tool: 'squad_week', input: {} }]);
      // 米亚 hasn't agreed to the current copy: her check-in wakes no one, and her name and
      // run are nowhere the model reads.
      expect(await wakes(fixture, { agent, consented: [fixture.leo] }).run()).toMatchObject({
        queued: 2,
        done: 2,
      });
      expect(runs).toHaveLength(1);
      const read = [runs[0]?.task, ...(runs[0]?.answers ?? [])].join('\n');
      expect(read).toContain('队员1');
      expect(read).not.toContain('米亚');
      expect(read).not.toContain('跑步');
    });
  });

  it('writes the 战术板 in the squad’s language and a check-in’s reply in its author’s', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => []);
      const week: SquadWeek = {
        ...fixture.week,
        members: fixture.week.members.map((member) => ({ ...member, language: 'en' })),
        language: 'zh-Hant',
      };
      await wakes(fixture, { agent, weeks: { [week.weekStart]: week } }).run();
      const daily = runs.find(({ task }) => task.includes('新的一天'))?.task;
      const checkIn = runs.find(({ task }) => task.includes('有人打卡'))?.task;
      expect(daily).toContain('战术板：用繁體中文寫，照台灣的說法。');
      expect(checkIn?.split('\n\n')).toContain('Write in English.');
    });
  });

  it('wakes for a check-in made on a day already in next week, as a member far east has it', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => []);
      // 10am Sunday in New York is Monday in Tokyo: the check-in is in the week of 11-02.
      const nextWeek: SquadWeek = {
        ...fixture.week,
        weekStart: '2026-11-02',
        checkIns: fixture.week.checkIns.map((checkIn) => ({ ...checkIn, day: '2026-11-02' })),
      };
      expect(
        await wakes(fixture, { agent, weeks: { '2026-11-02': nextWeek } }).run(),
      ).toMatchObject({ queued: 3, done: 3 });
      // The day's wake was queued first, from this week; then the check-in's, from next week's.
      expect(runs.map(({ task }) => task.includes('队员1 训练 跑步'))).toStrictEqual([false, true]);
    });
  });

  it('counts the tokens of a wake whose check-in was deleted while it ran, and drops its reply', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, checkIn } = fixture;
      const agent: CoachAgent = {
        async run({ task, tools }) {
          if (!task.includes('新的一天')) {
            const use = (name: string, input: unknown) =>
              tools.find((tool) => tool.name === name)?.run(input);
            await use('reply', { text: '腿还在吗' });
            await use('react', { emoji: '💪' });
            await sql`delete from public.check_ins where id = ${checkIn}`.execute(trx);
          }
          return {
            ok: true,
            usage: { requests: 1, inputTokens: 1_000, cachedInputTokens: 0, outputTokens: 10 },
          };
        },
      };
      const told: unknown[] = [];
      const replied: CoachReplied = (reply) => {
        told.push(reply);
        return Promise.resolve();
      };
      expect(await wakes(fixture, { agent, replied }).run()).toMatchObject({ queued: 3, done: 3 });
      expect(told).toStrictEqual([]);
      const usage = await sql<{ wake_id: string | null }>`
        select wake_id from public.coach_usage where squad_id = ${squad} order by id`.execute(trx);
      expect(usage.rows.map(({ wake_id }) => wake_id === null)).toStrictEqual([true, false]);
      // The reply to a check-in that went is dropped, and the wake still ends.
      const replies =
        await sql`select 1 from public.coach_replies where squad_id = ${squad}`.execute(trx);
      expect(replies.rows).toHaveLength(0);
    });
  });

  it('runs a reply’s wake before the squad’s older ones, so its answer doesn’t wait', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, leo, checkIn } = fixture;
      const stores = createPostgresCoachStores(trx);
      await stores.wakes.enqueue([{ squad, reason: { kind: 'daily', day: '2026-11-01' } }], now);
      const reply = await commentOn(fixture, {
        member: leo,
        text: '教练',
        at: now,
        toCoach: 'xiaohun',
      });
      const later = new Date(now.getTime() + 60_000);
      await stores.wakes.enqueue(
        [{ squad, reason: { kind: 'comment', checkIn, comment: reply.id } }],
        later,
      );
      expect(await stores.wakes.claim({ squads: [squad], limit: 1, now: later })).toMatchObject([
        { reason: { kind: 'comment', comment: reply.id } },
      ]);
    });
  });

  it('runs a squad’s wakes one at a time, and keeps its files append-only until it ends', async () => {
    await rolledBack(async ({ trx, squad }) => {
      const stores = createPostgresCoachStores(trx);
      await stores.wakes.enqueue([{ squad, reason: { kind: 'daily', day: '2026-11-01' } }], now);
      const [wake] = await stores.wakes.claim({ squads: [squad], limit: 1, now });
      if (wake === undefined) throw new Error('no wake claimed');
      // While it runs, another run leaves the squad alone, so its wakes run in order.
      await stores.wakes.enqueue([{ squad, reason: { kind: 'daily', day: '2026-11-02' } }], now);
      expect(await stores.wakes.claim({ squads: [squad], limit: 1, now })).toStrictEqual([]);
      // Until it has run so long that it must have stopped: it is taken back first, alone.
      const later = new Date(now.getTime() + 16 * 60_000);
      expect(await stores.wakes.claim({ squads: [squad], limit: 5, now: later })).toMatchObject([
        { id: wake.id },
      ]);
      await stores.wakes.finish(wake.id);
      expect(await stores.wakes.claim({ squads: [squad], limit: 5, now: later })).toMatchObject([
        { reason: { kind: 'daily', day: '2026-11-02' } },
      ]);
      await stores.memory.save({ squad, wake: wake.id, files: [{ path: 'memory.md', body: 'a' }] });
      await sql`savepoint attempt`.execute(trx);
      await expect(
        sql`update public.coach_files set body = 'b' where squad_id = ${squad}`.execute(trx),
      ).rejects.toThrow('coach_files is append-only');
      await sql`rollback to savepoint attempt`.execute(trx);
      // The wake may go (its check-in did), and the file keeps its body.
      await sql`delete from public.coach_wakes where id = ${wake.id}`.execute(trx);
      expect((await stores.memory.files(squad)).get('memory.md')).toBe('a');
      await sql`delete from public.squads where id = ${squad}`.execute(trx);
      expect((await stores.memory.files(squad)).size).toBe(0);
    });
  });
  it('previews a member’s day without saving or sending anything but its tokens', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      const given: unknown[] = [];
      const gifting: CoachGifting = {
        options: ({ members }) =>
          Promise.resolve({
            pool: [{ id: 'gift-scarf', description: '红围巾' }],
            open: new Map(members.map((each) => [each, []])),
          }),
        give: (input) => {
          given.push(input);
          return Promise.resolve(undefined);
        },
      };
      const { agent, runs } = scriptedAgent(() => [
        { tool: 'post_note', input: { text: '周日歇好' } },
        {
          tool: 'note_to',
          input: {
            member: '队员1',
            text: '今天多喝水',
            challenge: { title: '喝水', amount: 8, unit: '杯', line: '天干' },
          },
        },
        // Only the member previewed gets a note or a gift.
        { tool: 'note_to', input: { member: '队员2', text: '走走' } },
        { tool: 'give_gift', input: { member: '队员1', piece: 'gift-scarf', line: '天冷了' } },
        { tool: 'remember', input: { path: 'people/队员1.md', fact: '队员1爱喝水' } },
      ]);
      const preview = await wakes(fixture, { agent, gifting }).preview({ squad, member: mia });
      expect(runs).toHaveLength(1);
      expect(runs[0]?.answers).toStrictEqual([
        '已写上战术板。',
        '便条写好了，给 队员1，挑战「喝水 8 杯」。',
        '不能给 队员2 写便条；能写的是：队员1。',
        'gift-scarf 送给 队员1 了。',
        '记下了，在 people/队员1.md。',
      ]);
      expect(runs[0]?.task).toContain('今天给这些人各写一张便条');
      expect(preview).toMatchObject({
        ran: true,
        day: '2026-11-01',
        board: '周日歇好',
        note: {
          text: '今天多喝水',
          challenge: { title: '喝水', amount: 8, unit: '杯', line: '天干' },
        },
        gift: { piece: 'gift-scarf', line: '天冷了' },
        costMicros: 4600,
      });
      expect(preview.ran && preview.files.map(({ path }) => path)).toContain(`people/${mia}.md`);
      expect(given).toStrictEqual([]);
      const saved = await sql<{ notes: string; board: string; wakes: string; usage: string }>`
        select
          (select count(*) from public.coach_member_notes where squad_id = ${squad}) as notes,
          (select count(*) from public.coach_notes where squad_id = ${squad}) as board,
          (select count(*) from public.coach_wakes where squad_id = ${squad}) as wakes,
          (select count(*) from public.coach_usage where squad_id = ${squad} and wake_id is null) as usage
      `.execute(trx);
      expect(saved.rows).toStrictEqual([{ notes: '0', board: '0', wakes: '0', usage: '1' }]);
      expect(
        await wakes(fixture, { agent, gifting }).preview({ squad, member: randomUUID() }),
      ).toStrictEqual({
        ran: false,
        why: 'the member is not in the squad',
      });
    });
  });
  it('delivers a previewed note to the member alone when asked, once a day', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      const { agent } = scriptedAgent(() => [
        { tool: 'post_note', input: { text: '周日歇好' } },
        {
          tool: 'note_to',
          input: {
            member: '队员1',
            text: '今天多喝水',
            challenge: { title: '喝水', amount: 8, unit: '杯', line: '天干' },
          },
        },
      ]);
      const first = await wakes(fixture, { agent }).preview({ squad, member: mia, deliver: true });
      expect(first).toMatchObject({ ran: true, delivered: true, note: { text: '今天多喝水' } });
      const saved = await sql<{ member: string; text: string; title: string; board: string }>`
        select m.member_id as member, m.text, m.challenge_title as title,
          (select count(*) from public.coach_notes where squad_id = ${squad}) as board
        from public.coach_member_notes m where m.squad_id = ${squad}
      `.execute(trx);
      expect(saved.rows).toStrictEqual([
        { member: mia, text: '今天多喝水', title: '喝水', board: '0' },
      ]);
      const again = await wakes(fixture, { agent }).preview({ squad, member: mia, deliver: true });
      expect(again).toMatchObject({ ran: true, delivered: false });
      const plain = await wakes(fixture, { agent }).preview({ squad, member: mia });
      expect(plain.ran && 'delivered' in plain).toBe(false);
    });
  });
});
