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
        reasoning: row.reasoning,
        dreamModel: row.dream_model,
        dreamReasoning: row.dream_reasoning,
        rules: row.rules,
        wakes: row.wakes,
        noteHour: row.note_hour,
        holidays: StoredHolidays.parse(row.holidays).days,
      });
    },

    async save(settings, by) {
      const columns = {
        coaching: settings.coaching,
        model: settings.model,
        reasoning: settings.reasoning,
        dream_model: settings.dreamModel,
        dream_reasoning: settings.dreamReasoning,
        rules: settings.rules,
        wakes: settings.wakes,
        note_hour: settings.noteHour,
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
              sql<boolean>`(coaching, model, reasoning, dream_model, dream_reasoning, rules, wakes, note_hour, holidays) is distinct from (${columns.coaching}, ${columns.model}, ${columns.reasoning}, ${columns.dream_model}, ${columns.dream_reasoning}, ${columns.rules}, ${columns.wakes}, ${columns.note_hour}::integer, ${columns.holidays}::jsonb)`,
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
