import { sql, type Kysely } from 'kysely';

import { AwardSettings } from '../domain/settings.js';
import type { AwardSettingsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The award settings on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresAwardSettings(db: Kysely<DB>): AwardSettingsStore {
  return {
    async current() {
      const row = await db
        .selectFrom('weekly_award_settings')
        .selectAll()
        .executeTakeFirstOrThrow();
      return AwardSettings.parse({
        version: 1,
        model: row.model,
        instructions: row.instructions,
        moves: row.moves,
      });
    },

    async save(settings, by) {
      const moves = JSON.stringify(settings.moves);
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('weekly_award_settings')
            .set({ model: settings.model, instructions: settings.instructions, moves })
            .where(
              sql<boolean>`(model, instructions, moves) is distinct from (${settings.model}, ${settings.instructions}, ${moves}::jsonb)`,
            )
            .returning('only_row'),
        )
        .insertInto('weekly_award_setting_events')
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
