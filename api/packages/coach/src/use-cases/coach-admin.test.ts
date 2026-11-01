import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresCoachCatalog } from '../adapters/postgres-coach-catalog.js';
import {
  createPostgresCoachSettings,
  type CoachTables,
} from '../adapters/postgres-coach-settings.js';
import { CoachId, type CoachEdit } from '../domain/coach.js';
import { CoachSettingsChange, MemberId, SquadId } from '../domain/settings.js';
import { createCoachCatalog } from './coach-catalog.js';
import { createCoachSettings } from './coach-settings.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Each test changes the seeded
// rows inside a transaction it rolls back, so the other test files keep reading the seed.
const db = new Kysely<CoachTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

class RolledBack extends Error {}

async function rolledBack(test: (trx: Kysely<CoachTables>, admin: MemberId) => Promise<void>) {
  await expect(
    db.transaction().execute(async (trx) => {
      const id = randomUUID();
      await sql`insert into auth.users (id, email) values (${id}, ${`${id}@example.com`})`.execute(
        trx,
      );
      await test(trx, MemberId.parse(id));
      throw new RolledBack();
    }),
  ).rejects.toBeInstanceOf(RolledBack);
}

/** What `by` logged in `log`, oldest first: the settings' log, or the coaches'. */
const logged = async (
  trx: Kysely<CoachTables>,
  { log, by }: { log: 'coach_setting_events' | 'coach_catalog_events'; by: MemberId },
) =>
  (
    await sql<{ value: unknown }>`
      select to_jsonb(event) -> ${log === 'coach_setting_events' ? 'settings' : 'coach'} as value
      from ${sql.table(log)} as event
      where changed_by = ${by} order by id
    `.execute(trx)
  ).rows.map(({ value }) => value);

describe('the coach settings', () => {
  it('start with coaching off on GPT-6 Luna, as the migration saved them', async () => {
    const settings = await createCoachSettings({
      store: createPostgresCoachSettings(db),
    }).current();
    expect(settings).toMatchObject({
      version: 1,
      coaching: false,
      onlySquads: null,
      model: 'openai/gpt-6-luna',
      inputMicrosPerMillion: 0,
      outputMicrosPerMillion: 0,
    });
    expect(settings.rules).toContain('不提谁没打卡');
  });

  it('change only what is named, logging the whole new value once', async () => {
    await rolledBack(async (trx, admin) => {
      const settings = createCoachSettings({ store: createPostgresCoachSettings(trx) });
      const before = await settings.current();
      const trial = SquadId.parse('6f1c3e2a-8b4d-4c5e-9f60-7a8b9c0d1e2f');

      const changed = await settings.change(
        { coaching: true, onlySquads: [trial], inputMicrosPerMillion: 1_250_000 },
        admin,
      );
      const expected = {
        ...before,
        coaching: true,
        onlySquads: [trial],
        inputMicrosPerMillion: 1_250_000,
      };
      expect(changed).toStrictEqual(expected);
      expect(await settings.current()).toStrictEqual(expected);

      // The same change again saves nothing new.
      await settings.change({ coaching: true, onlySquads: [trial] }, admin);
      expect(await logged(trx, { log: 'coach_setting_events', by: admin })).toStrictEqual([
        expected,
      ]);

      // Back to every squad.
      await settings.change({ onlySquads: null }, admin);
      expect(await settings.current()).toMatchObject({ onlySquads: null });
      expect(await logged(trx, { log: 'coach_setting_events', by: admin })).toHaveLength(2);
    });
  });

  it('refuse a model that is not OpenAI’s, since the coach runs on the OpenAI Agents SDK', () => {
    expect(CoachSettingsChange.safeParse({ model: 'anthropic/claude-haiku-5-5' }).success).toBe(
      false,
    );
    expect(CoachSettingsChange.safeParse({ model: 'openai/gpt-6-luna' }).success).toBe(true);
  });
});

const nuannuan: CoachEdit = {
  id: CoachId.parse('nuannuan'),
  tier: 'entry',
  name: '暖暖',
  catchphrase: '今天也辛苦啦',
  credentials: '普拉提教练，持证（真的）。',
  style: '温柔、会夸人',
  soul: '你是暖暖，一个温柔的普拉提教练。',
  look: 'nuannuan',
  offered: true,
};

describe('the coaches', () => {
  it('start with 小混, the first 入门 coach', async () => {
    const coaches = await createCoachCatalog({ store: createPostgresCoachCatalog(db) }).list();
    expect(
      coaches.map(({ id, tier, name, look, offered }) => ({ id, tier, name, look, offered })),
    ).toStrictEqual([
      { id: 'xiaohun', tier: 'entry', name: '小混', look: 'xiaohun', offered: true },
    ]);
  });

  it('add a coach and replace one whole, logging each change once', async () => {
    await rolledBack(async (trx, admin) => {
      const catalog = createCoachCatalog({ store: createPostgresCoachCatalog(trx) });

      expect(await catalog.put(nuannuan, admin)).toStrictEqual({ version: 1, ...nuannuan });
      // The same coach again saves nothing new.
      await catalog.put(nuannuan, admin);
      const retired = { ...nuannuan, offered: false };
      await catalog.put(retired, admin);

      expect((await catalog.list()).map(({ id, offered }) => ({ id, offered }))).toStrictEqual([
        { id: 'nuannuan', offered: false },
        { id: 'xiaohun', offered: true },
      ]);
      expect(await logged(trx, { log: 'coach_catalog_events', by: admin })).toStrictEqual([
        { version: 1, ...nuannuan },
        { version: 1, ...retired },
      ]);
    });
  });

  it('are never deleted, and their log never changes', async () => {
    await rolledBack(async (trx) => {
      await sql`savepoint attempt`.execute(trx);
      await expect(
        sql`delete from public.coaches where id = 'xiaohun'`.execute(trx),
      ).rejects.toThrow('a coach is never deleted');
      await sql`rollback to savepoint attempt`.execute(trx);
      await expect(
        sql`update public.coach_catalog_events set coach = '{"version": 1}'`.execute(trx),
      ).rejects.toThrow('coach_catalog_events is append-only');
    });
  });
});
