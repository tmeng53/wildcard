import { sql, type Kysely } from 'kysely';

import { DiceLines } from '../domain/dice.js';
import type { DiceLinesStore } from '../ports.js';
import type { DB } from './tables.js';

/** The dice lines on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresDiceLines(db: Kysely<DB>): DiceLinesStore {
  return {
    async current(options) {
      const row = await db
        .selectFrom('disclaimer_dice')
        .select('lines')
        .$if(options?.forUpdate === true, (query) => query.forUpdate())
        .executeTakeFirstOrThrow();
      return DiceLines.parse({ version: 1, lines: row.lines });
    },

    async save(dice, by) {
      const lines = JSON.stringify(dice.lines);
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('disclaimer_dice')
            .set({ lines: sql`${lines}::jsonb` })
            .where(sql<boolean>`lines is distinct from ${lines}::jsonb`)
            .returning('only_row'),
        )
        .insertInto('disclaimer_dice_events')
        .columns(['changed_by', 'dice'])
        .expression((eb) =>
          eb
            .selectFrom('changed')
            .select([
              sql<string>`${by}::uuid`.as('changed_by'),
              sql<string>`${JSON.stringify(dice)}::jsonb`.as('dice'),
            ]),
        )
        .returning('id')
        .execute();
      return saved.length > 0;
    },
  };
}
