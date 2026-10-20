import { sql, type Kysely } from 'kysely';

import { StoredAwards } from '../domain/awards.js';
import type { AwardsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this module reads and writes, as generated from the migrations. */
export type WeeklyAwardTables = DB;

/** The awards store on Postgres (`supabase/migrations`). */
export function createPostgresAwardsStore(db: Kysely<WeeklyAwardTables>): AwardsStore {
  return {
    async find(squad, weekStart) {
      const row = await db
        .selectFrom('weekly_awards')
        .select(['awards', 'failed_attempts', 'last_error'])
        .where('squad_id', '=', squad)
        .where('week_start', '=', weekStart)
        .executeTakeFirst();
      if (row === undefined) return undefined;
      if (row.awards !== null) return { status: 'given', awards: StoredAwards.parse(row.awards) };
      return {
        status: 'failing',
        failures: {
          count: row.failed_attempts,
          ...(row.last_error === null ? {} : { lastError: row.last_error }),
        },
      };
    },

    async save({ squad, weekStart, awards }) {
      const saved = await db
        .insertInto('weekly_awards')
        .values({ squad_id: squad, week_start: weekStart, awards: JSON.stringify(awards) })
        .onConflict((conflict) =>
          conflict
            .columns(['squad_id', 'week_start'])
            .doUpdateSet({ awards: (eb) => eb.ref('excluded.awards') })
            .where('weekly_awards.awards', 'is', null),
        )
        .returning('squad_id')
        .executeTakeFirst();
      return saved !== undefined;
    },

    async recordFailure({ squad, weekStart, error }) {
      await db
        .insertInto('weekly_awards')
        .values({ squad_id: squad, week_start: weekStart, failed_attempts: 1, last_error: error })
        .onConflict((conflict) =>
          conflict.columns(['squad_id', 'week_start']).doUpdateSet({
            failed_attempts: sql`weekly_awards.failed_attempts + 1`,
            last_error: (eb) => eb.ref('excluded.last_error'),
          }),
        )
        .execute();
    },

    async markNudged(squad, weekStart) {
      // A nudge can come before the first try, when the run hasn't reached the squad (or isn't
      // running at all), so it may start the row.
      const marked = await db
        .insertInto('weekly_awards')
        .values({ squad_id: squad, week_start: weekStart, nudged_at: sql`now()` })
        .onConflict((conflict) =>
          conflict
            .columns(['squad_id', 'week_start'])
            .doUpdateSet({ nudged_at: sql`now()` })
            .where('weekly_awards.nudged_at', 'is', null)
            .where('weekly_awards.awards', 'is', null),
        )
        .returning('squad_id')
        .executeTakeFirst();
      return marked !== undefined;
    },

    async markNotified(squad, weekStart) {
      const marked = await db
        .updateTable('weekly_awards')
        .set({ notified_at: sql`now()` })
        .where('squad_id', '=', squad)
        .where('week_start', '=', weekStart)
        .where('notified_at', 'is', null)
        .where('awards', 'is not', null)
        .returning('squad_id')
        .executeTakeFirst();
      return marked !== undefined;
    },

    forget: (member) =>
      db.transaction().execute(async (trx) => {
        const rows = await trx
          .selectFrom('weekly_awards')
          .select(['squad_id', sql<string>`week_start::text`.as('week_start'), 'awards'])
          .where(sql<boolean>`awards @> ${JSON.stringify({ members: [{ member }] })}::jsonb`)
          .forUpdate()
          .execute();
        for (const row of rows) {
          const awards = StoredAwards.parse(row.awards);
          const kept = {
            ...awards,
            members: awards.members.filter((each) => each.member !== member),
          };
          await trx
            .updateTable('weekly_awards')
            .set({ awards: JSON.stringify(kept) })
            .where('squad_id', '=', row.squad_id)
            .where('week_start', '=', row.week_start)
            .execute();
        }
      }),
  };
}
