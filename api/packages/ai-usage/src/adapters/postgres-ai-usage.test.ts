import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { MemberId } from '../domain/settings.js';
import { createAiUsageSettings } from '../use-cases/ai-usage-settings.js';
import { createPostgresAiUsageLedger } from './postgres-ai-usage-ledger.js';
import { createPostgresAiUsageSettings, type AiUsageTables } from './postgres-ai-usage-settings.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Each test changes rows inside a
// transaction it rolls back, so the other test files keep reading the seed.
const db = new Kysely<AiUsageTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

class RolledBack extends Error {}

async function rolledBack(test: (trx: Kysely<AiUsageTables>, member: string) => Promise<void>) {
  await expect(
    db.transaction().execute(async (trx) => {
      const id = randomUUID();
      await sql`insert into auth.users (id, email) values (${id}, ${`${id}@example.com`})`.execute(
        trx,
      );
      await test(trx, id);
      throw new RolledBack();
    }),
  ).rejects.toBeInstanceOf(RolledBack);
}

const newSquad = async (trx: Kysely<AiUsageTables>) => {
  const id = randomUUID();
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${id})`.execute(
    trx,
  );
  return id;
};

const usage = { requests: 2, inputTokens: 100, cachedInputTokens: 40, outputTokens: 7 };

describe('the AI usage ledger on Postgres', () => {
  it('adds up what a squad and everyone spent since a moment, and a squad’s totals by feature', async () => {
    await rolledBack(async (trx, member) => {
      const ledger = createPostgresAiUsageLedger(trx);
      const squad = await newSquad(trx);
      const since = new Date('2030-01-02T00:00:00Z');
      const everyoneBefore = await ledger.spent({ since });
      const entry = {
        feature: 'coach-wake' as const,
        squad,
        member: undefined,
        model: 'openai/gpt-6-luna',
        usage,
        costMicros: 30,
        at: new Date('2030-01-02T01:00:00Z'),
      };
      await ledger.record(entry);
      await ledger.record({ ...entry, feature: 'disclaimer-drafts', member, costMicros: 12 });
      // The day before counts toward neither.
      await ledger.record({ ...entry, costMicros: 500, at: new Date('2030-01-01T23:59:59Z') });
      // A member without a squad spends from everyone's budget only.
      await ledger.record({ ...entry, squad: undefined, member, costMicros: 5 });

      expect(await ledger.spent({ squad, since })).toBe(42);
      expect((await ledger.spent({ since })) - everyoneBefore).toBe(47);
      expect(await ledger.total({ squad, features: ['coach-wake'], since })).toStrictEqual({
        calls: 1,
        requests: 2,
        inputTokens: 100,
        cachedInputTokens: 40,
        outputTokens: 7,
        costMicros: 30,
      });
      expect(
        (await ledger.total({ squad, features: ['coach-wake', 'disclaimer-drafts'] })).costMicros,
      ).toBe(542);
    });
  });

  it('keeps a call whose squad ended or whose member left meanwhile, unnamed', async () => {
    await rolledBack(async (trx) => {
      const ledger = createPostgresAiUsageLedger(trx);
      await ledger.record({
        feature: 'disclaimer-drafts',
        squad: randomUUID(),
        member: randomUUID(),
        model: 'openai/gpt-6-luna',
        usage,
        costMicros: 1,
        at: new Date('2030-02-01T00:00:00Z'),
      });
      const rows = await trx
        .selectFrom('ai_usage')
        .select(['squad_id', 'member_id'])
        .where('at', '=', new Date('2030-02-01T00:00:00Z'))
        .execute();
      expect(rows).toStrictEqual([{ squad_id: null, member_id: null }]);
    });
  });
});

describe('the AI usage settings', () => {
  it('start from the coach’s prices and caps, every model a setting names priced', async () => {
    const settings = await createPostgresAiUsageSettings(db).current();
    expect(Object.keys(settings.prices)).toContain('openai/gpt-6-luna');
    expect(settings.version).toBe(1);
  });

  it('change only what is named, logging the whole new value once', async () => {
    await rolledBack(async (trx, admin) => {
      const settings = createAiUsageSettings({ store: createPostgresAiUsageSettings(trx) });
      const by = MemberId.parse(admin);
      const before = await settings.current();
      const prices = {
        ...before.prices,
        'anthropic/claude-test': {
          inputMicrosPerMillion: 3_000_000,
          cachedInputMicrosPerMillion: 300_000,
          outputMicrosPerMillion: 15_000_000,
        },
      };
      const expected = { ...before, prices, squadDailyCapMicros: 250_000 };
      expect(await settings.change({ prices, squadDailyCapMicros: 250_000 }, by)).toStrictEqual(
        expected,
      );
      expect(await settings.current()).toStrictEqual(expected);
      // The same change again saves nothing new.
      await settings.change({ squadDailyCapMicros: 250_000 }, by);
      const logged = await trx
        .selectFrom('ai_usage_setting_events')
        .select('settings')
        .where('changed_by', '=', admin)
        .execute();
      expect(logged.map((row) => row.settings)).toStrictEqual([expected]);
    });
  });
});
