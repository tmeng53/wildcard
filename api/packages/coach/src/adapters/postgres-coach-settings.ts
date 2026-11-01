import { sql, type Kysely } from 'kysely';

import { CoachSettings } from '../domain/settings.js';
import type { CoachSettingsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables the coach stores read, as generated from the migrations. */
export type CoachTables = DB;

/** The coach settings on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresCoachSettings(db: Kysely<DB>): CoachSettingsStore {
  return {
    async current(options) {
      const row = await db
        .selectFrom('coach_settings')
        .selectAll()
        .$if(options?.forUpdate === true, (query) => query.forUpdate())
        .executeTakeFirstOrThrow();
      return CoachSettings.parse({
        version: 1,
        coaching: row.coaching,
        model: row.model,
        rules: row.rules,
        inputMicrosPerMillion: row.input_micros_per_million,
        outputMicrosPerMillion: row.output_micros_per_million,
      });
    },

    async save(settings, by) {
      const columns = {
        coaching: settings.coaching,
        model: settings.model,
        rules: settings.rules,
        input_micros_per_million: settings.inputMicrosPerMillion,
        output_micros_per_million: settings.outputMicrosPerMillion,
      };
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('coach_settings')
            .set(columns)
            .where(
              sql<boolean>`(coaching, model, rules, input_micros_per_million, output_micros_per_million) is distinct from (${columns.coaching}, ${columns.model}, ${columns.rules}, ${columns.input_micros_per_million}::integer, ${columns.output_micros_per_million}::integer)`,
            )
            .returning('only_row'),
        )
        .insertInto('coach_setting_events')
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
