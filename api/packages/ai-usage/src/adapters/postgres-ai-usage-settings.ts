import { sql, type Kysely } from 'kysely';
import { z } from 'zod';

import { AiUsageSettings } from '../domain/settings.js';
import { ModelName, ModelPrice } from '../domain/usage.js';
import type { AiUsageSettingsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this module reads and writes, as generated from the migrations. */
export type AiUsageTables = DB;

/** `ai_usage_settings.prices` as stored: each model's prices under the document's own version. */
const StoredPrices = z.strictObject({
  version: z.literal(1),
  models: z.record(ModelName, ModelPrice),
});

/** The settings on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresAiUsageSettings(db: Kysely<DB>): AiUsageSettingsStore {
  return {
    async current(options) {
      const row = await db
        .selectFrom('ai_usage_settings')
        .selectAll()
        .$if(options?.forUpdate === true, (query) => query.forUpdate())
        .executeTakeFirstOrThrow();
      return AiUsageSettings.parse({
        version: 1,
        prices: StoredPrices.parse(row.prices).models,
        squadDailyCapMicros: row.squad_daily_cap_micros,
        dailyCapMicros: row.daily_cap_micros,
      });
    },

    async save(settings, by) {
      const prices = JSON.stringify({ version: 1, models: settings.prices });
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('ai_usage_settings')
            .set({
              prices,
              squad_daily_cap_micros: settings.squadDailyCapMicros,
              daily_cap_micros: settings.dailyCapMicros,
            })
            .where(
              sql<boolean>`(prices, squad_daily_cap_micros, daily_cap_micros) is distinct from (${prices}::jsonb, ${settings.squadDailyCapMicros}::integer, ${settings.dailyCapMicros}::integer)`,
            )
            .returning('only_row'),
        )
        .insertInto('ai_usage_setting_events')
        .columns(['changed_by', 'settings'])
        .expression((eb) =>
          eb
            .selectFrom('changed')
            .select([
              sql<string>`${by}::uuid`.as('changed_by'),
              sql<string>`${JSON.stringify(settings)}::jsonb`.as('settings'),
            ]),
        )
        .returning('id')
        .execute();
      return saved.length > 0;
    },
  };
}
