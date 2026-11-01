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
  createPostgresCoachReport,
  createPostgresCoachStores,
} from '../adapters/postgres-coach-stores.js';
import { CoachId } from '../domain/coach.js';
import { MemberId, SquadId } from '../domain/settings.js';
import { CoachAlreadyHiredError, CoachNotOfferedError, NoCoachHiredError } from '../errors.js';
import type { SquadWeek } from '../domain/squad-week.js';
import type { AgentRun, CoachAgent, CoachTool } from '../ports.js';
import { createCoachHiring } from './coach-hiring.js';
import { createCoachSettings } from './coach-settings.js';
import { createCoachWakes } from './coach-wakes.js';

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
        answers.push(tool === undefined ? `no tool ${step.tool}` : await tool.run(step.input));
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
  }: {
    readonly agent: CoachAgent;
    readonly at?: Date;
    readonly weeks?: Readonly<Record<string, SquadWeek>>;
    readonly consented?: readonly string[];
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
  });
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
              { tool: 'read_file', input: { path: 'memory.md' } },
              { tool: 'post_note', input: { text: '  周日也跑了，队员1 是认真的  ' } },
            ]
          : [
              {
                tool: 'edit_file',
                input: { path: 'memory.md', find: '', replace: '- 队员1 周日跑步' },
              },
              {
                tool: 'edit_file',
                input: { path: 'people/队员2.md', find: '', replace: '还没打卡过' },
              },
              {
                tool: 'edit_file',
                input: { path: 'people/队员3.md', find: '', replace: '没这个人' },
              },
              { tool: 'post_note', input: { text: '不该有这个工具' } },
            ],
      );

      expect(await wakes(fixture, { agent }).run()).toStrictEqual({
        coaching: true,
        squads: 1,
        queued: 2,
        done: 2,
        failed: 0,
      });

      // The check-in's wake ran first: it may edit files but not post.
      expect(runs.map(({ tools }) => tools)).toStrictEqual([
        ['squad_week', 'read_file', 'edit_file'],
        ['squad_week', 'read_file', 'edit_file', 'post_note'],
      ]);
      expect(runs[0]?.task).toContain('队员1 练了 跑步');
      expect(runs[0]?.answers).toStrictEqual([
        '已改好，memory.md 现在 10 字。',
        '已改好，people/队员2.md 现在 5 字。',
        '没有 people/队员3.md 这个文件；能用的文件见任务里的列表。',
        'no tool post_note',
      ]);
      // The daily wake read what the first one wrote, and the instructions are 小混's.
      expect(runs[1]?.answers[1]).toBe('- 队员1 周日跑步');
      expect(runs[1]?.task).toContain('memory.md（10 字）');
      expect(runs[1]?.instructions).toContain('你是小混');
      expect(runs[1]?.instructions).toContain('不提谁没打卡');
      // How each wake goes is in the instructions, the same every time, so it can be cached.
      expect(runs[1]?.instructions).toContain('你会在两种时候醒来');
      expect(runs[0]?.instructions).toBe(runs[1]?.instructions);

      // A member's page is stored by their id, never by 队员N.
      const files = await sql<{ path: string; body: string; member_id: string | null }>`
        select path, body, member_id from public.coach_files where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(files.rows).toStrictEqual([
        // Members named in a file are stored by id, so a name follows them when 队员N shifts.
        { path: 'memory.md', body: `- {队员:${fixture.mia}} 周日跑步`, member_id: null },
        { path: `people/${leo}.md`, body: '还没打卡过', member_id: leo },
      ]);
      const notes = await sql<{ day: string; text: string; coach_id: string }>`
        select to_char(day, 'YYYY-MM-DD') as day, text, coach_id from public.coach_notes where squad_id = ${squad}`.execute(
        trx,
      );
      expect(notes.rows).toStrictEqual([
        { day: '2026-11-01', text: '周日也跑了，队员1 是认真的', coach_id: 'xiaohun' },
      ]);
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
        { tool: 'edit_file', input: { path: 'squad.md', find: '', replace: '队名：squad' } },
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
      expect(runs[2]?.task).toContain('squad.md（17 字）');

      const report = await createPostgresCoachReport(trx).squad(squad, tomorrow);
      expect(report).toMatchObject({
        coach: 'xiaohun',
        files: [{ path: 'squad.md', body: '队名：squad\n队名：squad\n队名：squad' }],
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

  it('saves no new version of a file an edit left as it was', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad } = fixture;
      const { agent, runs } = scriptedAgent(() => [
        { tool: 'edit_file', input: { path: 'memory.md', find: '', replace: '跑' } },
        { tool: 'edit_file', input: { path: 'memory.md', find: '跑', replace: '' } },
      ]);
      expect(await wakes(fixture, { agent }).run()).toMatchObject({ done: 2 });
      expect(runs).toHaveLength(2);
      const files = await sql<{ count: string }>`
        select count(*) from public.coach_files where squad_id = ${squad}`.execute(trx);
      expect(files.rows).toStrictEqual([{ count: '0' }]);
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
      expect(runs.map(({ task }) => task.includes('队员1 练了 跑步'))).toStrictEqual([false, true]);
    });
  });

  it('counts the tokens of a wake whose check-in was deleted while it ran', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, checkIn } = fixture;
      const agent: CoachAgent = {
        async run({ task }) {
          if (!task.includes('新的一天')) {
            await sql`delete from public.check_ins where id = ${checkIn}`.execute(trx);
          }
          return {
            ok: true,
            usage: { requests: 1, inputTokens: 1_000, cachedInputTokens: 0, outputTokens: 10 },
          };
        },
      };
      expect(await wakes(fixture, { agent }).run()).toMatchObject({ queued: 2, done: 2 });
      const usage = await sql<{ wake_id: string | null }>`
        select wake_id from public.coach_usage where squad_id = ${squad} order by id`.execute(trx);
      expect(usage.rows.map(({ wake_id }) => wake_id === null)).toStrictEqual([true, false]);
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
