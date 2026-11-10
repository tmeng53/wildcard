import { sql, type Kysely } from 'kysely';

import { MinimumBuild } from '../domain/minimum-build.js';
import type { MinimumBuildStore } from '../ports.js';
import type { DB } from './tables.js';

/** The minimum build on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresMinimumBuild(db: Kysely<DB>): MinimumBuildStore {
  return {
    async current() {
      const row = await db.selectFrom('minimum_build').select('build').executeTakeFirstOrThrow();
      return MinimumBuild.parse({ version: 1, build: row.build });
    },

    async save(minimum, by) {
      // One statement: the row changes only when the build differs, and the log gets the whole
      // new value exactly when it does.
      await db
        .with('changed', (cte) =>
          cte
            .updateTable('minimum_build')
            .set({ build: minimum.build })
            .where(sql<boolean>`build is distinct from ${minimum.build}::text`)
            .returning('only_row'),
        )
        .insertInto('minimum_build_events')
        .columns(['changed_by', 'minimum'])
        .expression((eb) =>
          eb
            .selectFrom('changed')
            .select([
              sql<string>`${by}::uuid`.as('changed_by'),
              sql<string>`${JSON.stringify(minimum)}::jsonb`.as('minimum'),
            ]),
        )
        .execute();
    },
  };
}
