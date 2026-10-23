import { sql, type Kysely } from 'kysely';

import { DraftSettings, ModelName } from '../domain/settings.js';
import type { DraftSettingsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The draft settings on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresDraftSettings(db: Kysely<DB>): DraftSettingsStore {
  return {
    async current() {
      const row = await db
        .selectFrom('disclaimer_draft_settings')
        .selectAll()
        .executeTakeFirstOrThrow();
      return DraftSettings.parse({
        version: 1,
        writing: row.writing,
        model: ModelName.parse(row.model),
        instructions: row.instructions,
        batchesPerDay: row.batches_per_day,
        memeChance: row.meme_chance,
      });
    },

    async save(settings, by) {
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('disclaimer_draft_settings')
            .set({
              writing: settings.writing,
              model: settings.model,
              instructions: settings.instructions,
              batches_per_day: settings.batchesPerDay,
              meme_chance: settings.memeChance,
            })
            .where(
              sql<boolean>`(writing, model, instructions, batches_per_day, meme_chance) is distinct from (${settings.writing}, ${settings.model}, ${settings.instructions}, ${settings.batchesPerDay}, ${settings.memeChance}::real)`,
            )
            .returning('only_row'),
        )
        .insertInto('disclaimer_draft_setting_events')
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
