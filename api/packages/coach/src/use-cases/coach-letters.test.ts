import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresCoachCatalog } from '../adapters/postgres-coach-catalog.js';
import { createPostgresCoachHiring } from '../adapters/postgres-coach-hiring.js';
import { createPostgresCoachLetters } from '../adapters/postgres-coach-letters.js';
import {
  createPostgresCoachSettings,
  type CoachTables,
} from '../adapters/postgres-coach-settings.js';
import {
  createPostgresCoachActivity,
  createPostgresCoachStores,
} from '../adapters/postgres-coach-stores.js';
import { CoachId } from '../domain/coach.js';
import { MemberId, SquadId } from '../domain/settings.js';
import type { SquadWeek } from '../domain/squad-week.js';
import type { AgentRun, CoachAgent } from '../ports.js';
import { createCoachActivity } from './coach-activity.js';
import { createCoachHiring } from './coach-hiring.js';
import { createCoachLetters, type CoachLettered } from './coach-letters.js';
import { createCoachSettings } from './coach-settings.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Each test works inside a
// transaction it rolls back.
const db = new Kysely<CoachTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

class RolledBack extends Error {}

const xiaohun = CoachId.parse('xiaohun');
const nuannuan = CoachId.parse('nuannuan');

interface Fixture {
  readonly trx: Kysely<CoachTables>;
  readonly squad: SquadId;
  readonly mia: string;
  readonly leo: string;
  readonly by: MemberId;
  readonly hiring: ReturnType<typeof createCoachHiring>;
  /** When the transaction began: every hire and firing in it is logged at this moment. */
  readonly began: Date;
}

/**
 * A squad of two that hired 小混, with a second coach 暖暖 to change to, coaching on, and 小混's
 * memory of both members.
 */
async function rolledBack(test: (fixture: Fixture) => Promise<void>) {
  await db
    .transaction()
    .execute(async (trx) => {
      const [mia, leo, squadId] = [randomUUID(), randomUUID(), randomUUID()];
      for (const id of [mia, leo]) {
        await sql`insert into auth.users (id, email) values (${id}, ${`${id}@example.com`})`.execute(
          trx,
        );
      }
      await sql`insert into public.squads (id, name, invite_code) values (${squadId}, 'squad', ${squadId})`.execute(
        trx,
      );
      const squad = SquadId.parse(squadId);
      const by = MemberId.parse(mia);
      await createCoachSettings({ store: createPostgresCoachSettings(trx) }).change(
        { coaching: true, inputMicrosPerMillion: 250_000, outputMicrosPerMillion: 2_000_000 },
        by,
      );
      const catalog = createPostgresCoachCatalog(trx);
      const first = (await catalog.list()).find(({ id }) => id === xiaohun);
      if (first === undefined) throw new Error('No coach.');
      await catalog.save({ ...first, id: nuannuan, name: '暖暖', soul: '你是暖暖。' }, by);
      const hiring = createCoachHiring({ hiring: createPostgresCoachHiring(trx), catalog });
      await hiring.hire({ squad, coach: xiaohun, by });
      await sql`insert into public.coach_files (squad_id, member_id, path, body) values
        (${squad}, null, 'squad.md', '周日晚上最热闹'),
        (${squad}, ${mia}, ${`people/${mia}.md`}, ${`{队员:${mia}} 周三雷打不动游泳`}),
        (${squad}, ${leo}, ${`people/${leo}.md`}, '备战半马')`.execute(trx);
      const { began } = z
        .object({ began: z.date() })
        .parse((await sql`select now() as began`.execute(trx)).rows[0]);
      await test({ trx, squad, mia, leo, by, hiring, began });
      throw new RolledBack();
    })
    .catch((error: unknown) => {
      if (!(error instanceof RolledBack)) throw error;
    });
}

/**
 * An agent that hands in each text with the tool it is given (`fail` fails the run), and records
 * each run.
 */
function writingAgent(texts: readonly string[]) {
  const runs: {
    instructions: string;
    task: string;
    tools: string[];
    answers: string[];
  }[] = [];
  const agent: CoachAgent = {
    async run({ instructions, task, tools }): Promise<AgentRun> {
      const usage = { requests: 1, inputTokens: 4_000, cachedInputTokens: 0, outputTokens: 300 };
      const answers: string[] = [];
      runs.push({
        instructions,
        task,
        tools: tools.map(({ name }) => name),
        answers,
      });
      for (const text of texts) {
        if (text === 'fail') return { ok: false, usage, error: 'TimeoutError: too slow' };
        const answer = await tools[0]?.run({ text });
        answers.push(typeof answer === 'string' ? answer : '');
      }
      return { ok: true, usage };
    },
  };
  return { agent, runs };
}

function letters(
  { trx, mia, leo, began }: Fixture,
  {
    agent,
    at = new Date(began.getTime() + 5_000),
    consented = [mia, leo],
    lettered,
    consentUnread = false,
  }: {
    readonly agent?: CoachAgent;
    readonly at?: Date;
    readonly consented?: readonly string[];
    readonly lettered?: CoachLettered;
    /** The consents can't be read, as when the database is briefly away. */
    readonly consentUnread?: boolean;
  },
) {
  const stores = createPostgresCoachStores(trx);
  const week: SquadWeek = {
    weekStart: '2026-11-02',
    members: [
      { member: mia, nickname: '米亚' },
      { member: leo, nickname: '阿杰' },
    ],
    checkIns: [],
  };
  return createCoachLetters({
    settings: createPostgresCoachSettings(trx),
    catalog: createPostgresCoachCatalog(trx),
    letters: createPostgresCoachLetters(trx),
    memory: stores.memory,
    usage: stores.usage,
    squadWeek: () => Promise.resolve(week),
    aiConsented: (members) =>
      consentUnread
        ? Promise.reject(new Error('The consents can’t be read.'))
        : Promise.resolve(members.filter((member) => consented.includes(member))),
    clock: () => at,
    timeZonesAt: () => Promise.resolve(() => 'America/New_York'),
    ...(agent === undefined ? {} : { agent }),
    ...(lettered === undefined ? {} : { lettered }),
  });
}

const usageRows = async ({ trx, squad }: Fixture) =>
  (
    await sql<{
      coach_id: string;
      wake_id: string | null;
    }>`select coach_id, wake_id from public.coach_usage where squad_id = ${squad}`.execute(trx)
  ).rows;

describe('the outgoing coach’s letter', () => {
  it('is written once a change of coach, in its own voice, for the whole squad', async () => {
    await rolledBack(async (fixture) => {
      const { squad, mia, leo, by, hiring, trx } = fixture;
      await hiring.change({ squad, coach: nuannuan, by });
      const { agent, runs } = writingAgent(['这队交给你了。\n米亚周三雷打不动去游泳。']);
      const told: { letter: number; members: readonly string[] }[] = [];
      const write = letters(fixture, {
        agent,
        lettered: (letter, members) => {
          told.push({ letter: letter.id, members });
          return Promise.resolve();
        },
      });

      const letter = await write.write(squad);
      expect(letter).toMatchObject({
        squad,
        from: { id: 'xiaohun', look: 'xiaohun' },
        to: { id: 'nuannuan', name: '暖暖' },
        text: '这队交给你了。\n米亚周三雷打不动去游泳。',
      });
      // 小混's own instructions and only its letter to write.
      expect(runs).toHaveLength(1);
      const [run] = runs;
      expect(run?.tools).toStrictEqual(['write_letter']);
      expect(run?.instructions).toContain('你是小混');
      expect(run?.task).toContain('接手的是暖暖');
      // A goodbye to the squad and the next coach, never a briefing between coaches.
      expect(run?.task).toContain('给小队和暖暖留一封告别信，全队都会看到');
      expect(run?.task).toContain('不写谁住哪、做什么工作、私下说过什么');
      expect(run?.task).toContain('- 队员1：米亚\n- 队员2：阿杰');
      // Its memory, members by the names the model knows them by.
      expect(run?.task).toContain('【people/队员1.md】\n队员1 周三雷打不动游泳');
      expect(run?.task).toContain('【squad.md】\n周日晚上最热闹');
      expect(run?.task).not.toContain('回来');
      // The tokens count toward the squad's cap, with no wake.
      expect(await usageRows(fixture)).toStrictEqual([{ coach_id: 'xiaohun', wake_id: null }]);
      // Everyone in the squad is told.
      expect(told).toStrictEqual([{ letter: letter?.id, members: [mia, leo] }]);

      // A retry answers the same letter and pays for nothing.
      expect(await write.write(squad)).toStrictEqual(letter);
      expect(runs).toHaveLength(1);
      // Members read it with the coach's activity while 暖暖 is their coach.
      const activity = createCoachActivity({ store: createPostgresCoachActivity(trx) });
      expect((await activity.squad({ squad, checkIns: [] })).letter).toStrictEqual(letter);
      await hiring.fire({ squad, by });
      expect((await activity.squad({ squad, checkIns: [] })).letter).toBeUndefined();
    });
  });

  it('leaves out the pages of members who didn’t agree to AI use', async () => {
    await rolledBack(async (fixture) => {
      const { squad, by, hiring, mia } = fixture;
      await hiring.change({ squad, coach: nuannuan, by });
      const { agent, runs } = writingAgent(['交给你了。']);
      await letters(fixture, { agent, consented: [mia] }).write(squad);
      expect(runs[0]?.task).toContain('队员1 周三雷打不动游泳');
      expect(runs[0]?.task).not.toContain('备战半马');
      expect(runs[0]?.task).not.toContain('阿杰');
    });
  });

  it('greets a coach coming back as one', async () => {
    await rolledBack(async (fixture) => {
      const { squad, by, hiring } = fixture;
      await hiring.change({ squad, coach: nuannuan, by });
      await hiring.change({ squad, coach: xiaohun, by });
      const { agent, runs } = writingAgent(['你又回来了。']);
      expect(await letters(fixture, { agent }).write(squad)).toMatchObject({
        from: { id: 'nuannuan' },
        to: { id: 'xiaohun' },
      });
      expect(runs[0]?.instructions).toContain('你是暖暖');
      expect(runs[0]?.task).toContain('小混以前带过这个小队，这次是回来。');
      expect(runs[0]?.task).toMatch(/- 小混：\d{4}-\d\d-\d\d 到 \d{4}-\d\d-\d\d\n- 暖暖：/);
    });
  });

  it('asks again for a letter too long, and never cuts one', async () => {
    await rolledBack(async (fixture) => {
      const { squad, by, hiring } = fixture;
      await hiring.change({ squad, coach: nuannuan, by });
      const { agent, runs } = writingAgent(['长'.repeat(201), '队员2 交给你了', '短的。']);
      expect(await letters(fixture, { agent }).write(squad)).toMatchObject({ text: '短的。' });
      expect(runs[0]?.answers).toStrictEqual([
        '太长了：201 字，最多 200 字。重写一封。',
        '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。重写一封。',
        '交上了。',
      ]);
    });
  });

  it('is none without a change just made, over the cap, or when the coach can’t write it', async () => {
    await rolledBack(async (fixture) => {
      const { squad, by, hiring, trx, began } = fixture;
      const { agent, runs } = writingAgent(['交给你了。']);
      // A squad's first coach replaced no one.
      expect(await letters(fixture, { agent }).write(squad)).toBeUndefined();
      await hiring.change({ squad, coach: nuannuan, by });
      // Asked after the moment passed.
      const late = new Date(began.getTime() + 3 * 60_000);
      expect(await letters(fixture, { agent, at: late }).write(squad)).toBeUndefined();
      // Without a model.
      expect(await letters(fixture, {}).write(squad)).toBeUndefined();
      // Over the squad's cap for the day.
      await sql`insert into public.coach_usage (squad_id, coach_id, model, requests, input_tokens, output_tokens, cost_micros)
        values (${squad}, 'xiaohun', 'openai/gpt', 1, 1, 1, 50000)`.execute(trx);
      expect(await letters(fixture, { agent }).write(squad)).toBeUndefined();
      expect(runs).toHaveLength(0);
    });
    await rolledBack(async (fixture) => {
      const { squad, by, hiring } = fixture;
      await hiring.change({ squad, coach: nuannuan, by });
      // A run that fails leaves no letter, and isn't tried again.
      const failing = writingAgent(['fail']);
      expect(await letters(fixture, { agent: failing.agent }).write(squad)).toBeUndefined();
      const after = writingAgent(['交给你了。']);
      expect(await letters(fixture, { agent: after.agent }).write(squad)).toBeUndefined();
      expect(after.runs).toHaveLength(0);
      expect(await usageRows(fixture)).toHaveLength(1);
    });
    await rolledBack(async (fixture) => {
      const { squad, by, hiring } = fixture;
      await hiring.change({ squad, coach: nuannuan, by });
      // What the coach reads failing to load leaves the change's one try for the retry.
      const unread = writingAgent(['交给你了。']);
      await expect(
        letters(fixture, { agent: unread.agent, consentUnread: true }).write(squad),
      ).rejects.toThrow('can’t be read');
      expect(unread.runs).toHaveLength(0);
      const retry = writingAgent(['交给你了。']);
      expect((await letters(fixture, { agent: retry.agent }).write(squad))?.text).toBe(
        '交给你了。',
      );
    });
  });

  it('is read only for the hire it was written for', async () => {
    await rolledBack(async (fixture) => {
      const { squad, trx, by } = fixture;
      const coachNow = async (coach: string, since: string) => {
        await sql`delete from public.squad_coaches where squad_id = ${squad}`.execute(trx);
        await sql`insert into public.squad_coaches (squad_id, coach_id, hired_by, hired_at)
          values (${squad}, ${coach}, ${by}, now() - ${since}::interval)`.execute(trx);
      };
      // 小混 is changed for 暖暖 two hours ago.
      await sql`insert into public.squad_coach_events (squad_id, kind, coach_id, changed_by, at) values
        (${squad}, 'fired', 'xiaohun', ${by}, now() - interval '2 hours'),
        (${squad}, 'hired', 'nuannuan', ${by}, now() - interval '2 hours')`.execute(trx);
      await coachNow('nuannuan', '2 hours');
      const store = createPostgresCoachLetters(trx);
      const handover = await store.handover(squad);
      if (handover === undefined) throw new Error('No change.');
      // While its letter is being written, 暖暖 is fired and hired again, with no change.
      await sql`insert into public.squad_coach_events (squad_id, kind, coach_id, changed_by, at) values
        (${squad}, 'fired', 'nuannuan', ${by}, now() - interval '90 minutes'),
        (${squad}, 'hired', 'nuannuan', ${by}, now() - interval '1 hour')`.execute(trx);
      await coachNow('nuannuan', '1 hour');
      await store.claim(handover);
      await store.save({ handover, day: '2026-11-08', text: '交给你了。' });
      // Saved after that hire, it still belongs to the change before.
      expect((await store.ofHandover(handover.hireEvent))?.text).toBe('交给你了。');
      const activity = createCoachActivity({ store: createPostgresCoachActivity(trx) });
      expect((await activity.squad({ squad, checkIns: [] })).letter).toBeUndefined();
    });
  });

  it('is none for a coach hired after a plain firing (解雇)', async () => {
    await rolledBack(async (fixture) => {
      const { squad, trx, by } = fixture;
      // Fired, then another hired later: two steps, at two moments.
      await sql`delete from public.squad_coaches where squad_id = ${squad}`.execute(trx);
      await sql`insert into public.squad_coach_events (squad_id, kind, coach_id, changed_by, at)
        values (${squad}, 'fired', 'xiaohun', ${by}, now() - interval '1 hour')`.execute(trx);
      await createPostgresCoachHiring(trx).hire({ squad, coach: nuannuan, by });
      const { agent, runs } = writingAgent(['交给你了。']);
      expect(await letters(fixture, { agent }).write(squad)).toBeUndefined();
      expect(runs).toHaveLength(0);
    });
  });
});
