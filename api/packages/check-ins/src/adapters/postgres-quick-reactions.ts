import { sql, type Kysely } from 'kysely';

import { QuickReactions } from '../domain/quick-reactions.js';
import type { QuickReactionsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The reaction bar's quick emoji on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresQuickReactions(db: Kysely<DB>): QuickReactionsStore {
  return {
    async current() {
      const row = await db.selectFrom('quick_reactions').select('emoji').executeTakeFirstOrThrow();
      return QuickReactions.parse({ version: 1, emoji: row.emoji });
    },

    async save(reactions, by) {
      const emoji = JSON.stringify(reactions.emoji);
      // One statement: the row changes only when the list differs, and the log gets the whole
      // new value exactly when it does.
      await db
        .with('changed', (cte) =>
          cte
            .updateTable('quick_reactions')
            .set({ emoji })
            .where(sql<boolean>`emoji is distinct from ${emoji}::jsonb`)
            .returning('only_row'),
        )
        .insertInto('quick_reaction_events')
        .columns(['changed_by', 'reactions'])
        .expression((eb) =>
          eb
            .selectFrom('changed')
            .select([
              sql<string>`${by}::uuid`.as('changed_by'),
              sql<string>`${JSON.stringify(reactions)}::jsonb`.as('reactions'),
            ]),
        )
        .execute();
    },
  };
}
