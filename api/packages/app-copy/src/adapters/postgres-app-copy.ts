import { sql, type Kysely } from 'kysely';

import { AppCopy } from '../domain/app-copy.js';
import type { AppCopyStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables the copy store reads, as generated from the migrations. */
export type AppCopyTables = DB;

/** The copy on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresAppCopy(db: Kysely<DB>): AppCopyStore {
  return {
    async current(options) {
      const row = await db
        .selectFrom('app_copy')
        .select('entries')
        .$if(options?.forUpdate === true, (query) => query.forUpdate())
        .executeTakeFirstOrThrow();
      return AppCopy.parse({ version: 1, entries: row.entries });
    },

    async save(copy, by) {
      const entries = JSON.stringify(copy.entries);
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('app_copy')
            .set({ entries: sql`${entries}::jsonb` })
            .where(sql<boolean>`entries is distinct from ${entries}::jsonb`)
            .returning('only_row'),
        )
        .insertInto('app_copy_events')
        .columns(['changed_by', 'copy'])
        .expression((eb) =>
          eb
            .selectFrom('changed')
            .select([
              sql<string>`${by}::uuid`.as('changed_by'),
              sql<string>`${JSON.stringify(copy)}::jsonb`.as('copy'),
            ]),
        )
        .returning('id')
        .execute();
      return saved.length > 0;
    },
  };
}
