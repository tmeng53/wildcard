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
  CoachNoteNotFoundError,
  CoachNotOfferedError,
  CoachSquadNotFoundError,
  NoCoachHiredError,
} from '../errors.js';
import { weekText, type SquadWeek } from '../domain/squad-week.js';
import type {
  AgentRun,
  CoachAgent,
  CoachMemberFacts,
  CoachPhotoUrls,
  CoachTool,
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
            reactions: 0,
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
  { trx, week }: Fixture,
  {
    agent,
    at = now,
    weeks,
    consented,
    replied,
    answered,
    photoUrls,
    memberFacts,
  }: {
    readonly agent: CoachAgent;
    readonly at?: Date;
    readonly weeks?: Readonly<Record<string, SquadWeek>>;
    readonly consented?: readonly string[];
    readonly replied?: CoachReplied;
    readonly answered?: CoachAnswered;
    readonly photoUrls?: CoachPhotoUrls;
    readonly memberFacts?: CoachMemberFacts;
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
    hiring: createPostgresCoachHiring(trx),
    clock: () => at,
    ...(replied === undefined ? {} : { replied }),
    ...(answered === undefined ? {} : { answered }),
    ...(photoUrls === undefined ? {} : { photoUrls }),
    ...(memberFacts === undefined ? {} : { memberFacts }),
  });
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

      expect(await wakes(fixture, { agent, replied }).run()).toStrictEqual({
        coaching: true,
        squads: 1,
        queued: 2,
        done: 2,
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
        '今天给这些人各写一张便条：\n- 队员1：这周已经练了 1 天。\n- 队员2：这周已经练了 0 天。',
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
      expect(runs[1]?.instructions).toContain('你会在三种时候醒来');
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
      // Both earlier wakes added a line; the new hire reads them.
      expect(runs[2]?.task).toContain('【memory.md】\n队名：squad\n队名：squad');

      const report = await createPostgresCoachReport(trx).squad(squad, tomorrow);
      expect(report).toMatchObject({
        coach: 'xiaohun',
        files: [
          { path: 'memory.md', body: '队名：squad\n队名：squad\n队名：squad' },
          // Started once, on the first wake.
          { path: 'squad.md' },
        ],
        usage: {
          total: {
            wakes: 3,
            requests: 6,
            inputTokens: 36_000,
            cachedInputTokens: 0,
            outputTokens: 2_400,
            costMicros: 13_800,
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
        { squad, checkIn, comment: first.id, commenter: leo, coach: 'xiaohun', text: '你也来跑' },
        { squad, checkIn, comment: second.id, commenter: mia, coach: 'xiaohun', text: '喊破嗓子' },
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
            reactions: 0,
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
        reactions: 1,
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
        '昨天（周六）小队的动态：\n- 10-31 周六 队员2 健康餐 「自己做的」 · 1 个表情',
      );
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
        reactions: 0,
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

  it('saves no new version of a file an edit left as it was', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad } = fixture;
      const { agent, runs } = scriptedAgent(() => [
        { tool: 'edit_file', input: { path: 'memory.md', find: '', replace: '跑' } },
        { tool: 'edit_file', input: { path: 'memory.md', find: '跑', replace: '' } },
      ]);
      expect(await wakes(fixture, { agent }).run()).toMatchObject({ done: 2 });
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
        queued: 1,
        done: 1,
      });
      expect(runs).toHaveLength(1);
      const read = [runs[0]?.task, ...(runs[0]?.answers ?? [])].join('\n');
      expect(read).toContain('队员1');
      expect(read).not.toContain('米亚');
      expect(read).not.toContain('跑步');
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
      ).toMatchObject({ queued: 2, done: 2 });
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
      expect(await wakes(fixture, { agent, replied }).run()).toMatchObject({ queued: 2, done: 2 });
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
});
