import { sql, type Kysely } from 'kysely';
import { z } from 'zod';

import { CoachHoliday, CoachSettings } from '../domain/settings.js';
import type { CoachSettingsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables the coach stores read, as generated from the migrations. */
export type CoachTables = DB;

/** `coach_settings.holidays` as stored: the calendar's days under the document's own version. */
const StoredHolidays = z.strictObject({ version: z.literal(1), days: z.array(CoachHoliday) });

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
        wakes: row.wakes,
        inputMicrosPerMillion: row.input_micros_per_million,
        cachedInputMicrosPerMillion: row.cached_input_micros_per_million,
        outputMicrosPerMillion: row.output_micros_per_million,
        noteHour: row.note_hour,
        squadDailyCapMicros: row.squad_daily_cap_micros,
        dailyCapMicros: row.daily_cap_micros,
        holidays: StoredHolidays.parse(row.holidays).days,
      });
    },

    async save(settings, by) {
      const columns = {
        coaching: settings.coaching,
        model: settings.model,
        rules: settings.rules,
        wakes: settings.wakes,
        input_micros_per_million: settings.inputMicrosPerMillion,
        cached_input_micros_per_million: settings.cachedInputMicrosPerMillion,
        output_micros_per_million: settings.outputMicrosPerMillion,
        note_hour: settings.noteHour,
        squad_daily_cap_micros: settings.squadDailyCapMicros,
        daily_cap_micros: settings.dailyCapMicros,
        holidays: JSON.stringify({ version: 1, days: settings.holidays }),
      };
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('coach_settings')
            .set(columns)
            .where(
              sql<boolean>`(coaching, model, rules, wakes, input_micros_per_million, cached_input_micros_per_million, output_micros_per_million, note_hour, squad_daily_cap_micros, daily_cap_micros, holidays) is distinct from (${columns.coaching}, ${columns.model}, ${columns.rules}, ${columns.wakes}, ${columns.input_micros_per_million}::integer, ${columns.cached_input_micros_per_million}::integer, ${columns.output_micros_per_million}::integer, ${columns.note_hour}::integer, ${columns.squad_daily_cap_micros}::integer, ${columns.daily_cap_micros}::integer, ${columns.holidays}::jsonb)`,
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
