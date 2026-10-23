import { sql, type Kysely } from 'kysely';

import { WeekSummaryWords } from '../domain/week-summary-words.js';
import type { WeekSummaryWordsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The Sunday summary's words on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresWeekSummaryWords(db: Kysely<DB>): WeekSummaryWordsStore {
  return {
    async current(options) {
      const row = await db
        .selectFrom('week_summary_words')
        .select('words')
        .$if(options?.forUpdate === true, (query) => query.forUpdate())
        .executeTakeFirstOrThrow();
      return WeekSummaryWords.parse(row.words);
    },

    async save(words, by) {
      const value = JSON.stringify(words);
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('week_summary_words')
            .set({ words: value })
            .where(sql<boolean>`words is distinct from ${value}::jsonb`)
            .returning('only_row'),
        )
        .insertInto('week_summary_word_events')
        .columns(['changed_by', 'words'])
        .expression((eb) =>
          eb
            .selectFrom('changed')
            .select([
              sql<string>`${by}::uuid`.as('changed_by'),
              sql<string>`${value}::jsonb`.as('words'),
            ]),
        )
        .returning('id')
        .execute();
      return saved.length > 0;
    },
  };
}
