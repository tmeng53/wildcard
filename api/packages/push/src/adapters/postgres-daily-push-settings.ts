import { sql, type Kysely } from 'kysely';

import { DailyPushSettings } from '../domain/daily-push-settings.js';
import type { DailyPushSettingsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The daily push's settings on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresDailyPushSettings(db: Kysely<DB>): DailyPushSettingsStore {
  return {
    async current(options) {
      const row = await db
        .selectFrom('daily_push_settings')
        .select(['sending', 'hour'])
        .$if(options?.forUpdate === true, (query) => query.forUpdate())
        .executeTakeFirstOrThrow();
      return DailyPushSettings.parse({ version: 1, ...row });
    },

    async save(settings, by) {
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('daily_push_settings')
            .set({ sending: settings.sending, hour: settings.hour })
            .where(
              sql<boolean>`(sending, hour) is distinct from (${settings.sending}::boolean, ${settings.hour}::integer)`,
            )
            .returning('only_row'),
        )
        .insertInto('daily_push_setting_events')
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
