import { sql, type Kysely } from 'kysely';

import { MemberId, StoredAward, titlesWonOf } from '../domain/awards.js';
import type { AwardsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this module reads and writes, as generated from the migrations. */
export type WeeklyAwardTables = DB;

/**
 * The awards store on Postgres (`supabase/migrations`): a row per squad-week for how the tries
 * went, and a row per winner, which a deleted account takes with it.
 */
export function createPostgresAwardsStore(db: Kysely<WeeklyAwardTables>): AwardsStore {
  return {
    async find(squad, weekStart) {
      const row = await db
        .selectFrom('weekly_awards')
        .select(['given_at', 'failed_attempts', 'last_error'])
        .where('squad_id', '=', squad)
        .where('week_start', '=', weekStart)
        .executeTakeFirst();
      if (row === undefined) return undefined;
      if (row.given_at === null) {
        return {
          status: 'failing',
          failures: {
            count: row.failed_attempts,
            ...(row.last_error === null ? {} : { lastError: row.last_error }),
          },
        };
      }
      const winners = await db
        .selectFrom('weekly_award_winners')
        .select(['member_id', 'award'])
        .where('squad_id', '=', squad)
        .where('week_start', '=', weekStart)
        .orderBy('position')
        .execute();
      return {
        status: 'given',
        awards: {
          members: winners.map(({ member_id, award }) => {
            const { titles, topCheckIn } = StoredAward.parse(award);
            return {
              member: MemberId.parse(member_id),
              titles,
              ...(topCheckIn === undefined ? {} : { topCheckIn }),
            };
          }),
        },
      };
    },

    async titlesWon(member) {
      const rows = await db
        .selectFrom('weekly_award_winners')
        .select('award')
        .where('member_id', '=', member)
        .orderBy('week_start', 'desc')
        .orderBy('squad_id')
        .execute();
      return titlesWonOf(rows.map(({ award }) => StoredAward.parse(award)));
    },

    save: ({ squad, weekStart, awards }) =>
      db.transaction().execute(async (trx) => {
        const given = await trx
          .insertInto('weekly_awards')
          .values({ squad_id: squad, week_start: weekStart, given_at: sql`now()` })
          .onConflict((conflict) =>
            conflict
              .columns(['squad_id', 'week_start'])
              .doUpdateSet({ given_at: sql`now()` })
              .where('weekly_awards.given_at', 'is', null),
          )
          .returning('squad_id')
          .executeTakeFirst();
        if (given === undefined) return false;
        if (awards.members.length > 0) {
          // A member whose account was deleted since the week was read fails the foreign key,
          // and the whole save with it: the next run reads the squad again.
          await trx
            .insertInto('weekly_award_winners')
            .values(
              awards.members.map(({ member, titles, topCheckIn }, position) => {
                const award: StoredAward = {
                  version: 1,
                  titles: [...titles],
                  ...(topCheckIn === undefined ? {} : { topCheckIn }),
                };
                return {
                  squad_id: squad,
                  week_start: weekStart,
                  member_id: member,
                  position,
                  award: JSON.stringify(award),
                };
              }),
            )
            .execute();
        }
        return true;
      }),

    async recordFailure({ squad, weekStart, error }) {
      await db
        .insertInto('weekly_awards')
        .values({ squad_id: squad, week_start: weekStart, failed_attempts: 1, last_error: error })
        .onConflict((conflict) =>
          conflict
            .columns(['squad_id', 'week_start'])
            .doUpdateSet({
              failed_attempts: sql`weekly_awards.failed_attempts + 1`,
              last_error: (eb) => eb.ref('excluded.last_error'),
            })
            .where('weekly_awards.given_at', 'is', null),
        )
        .execute();
    },

    async claimNudge(squad, weekStart) {
      // A nudge can come before the first try, when the run hasn't reached the squad (or isn't
      // running at all), so it may start the row.
      const claimed = await db
        .insertInto('weekly_awards')
        .values({ squad_id: squad, week_start: weekStart, nudged_failures: 0 })
        .onConflict((conflict) =>
          conflict
            .columns(['squad_id', 'week_start'])
            .doUpdateSet({ nudged_failures: sql`weekly_awards.failed_attempts` })
            .where('weekly_awards.given_at', 'is', null)
            .where((eb) =>
              eb.or([
                eb('weekly_awards.nudged_failures', 'is', null),
                eb('weekly_awards.nudged_failures', '<', eb.ref('weekly_awards.failed_attempts')),
              ]),
            ),
        )
        .returning(['failed_attempts', 'last_error'])
        .executeTakeFirst();
      if (claimed === undefined) return undefined;
      return {
        count: claimed.failed_attempts,
        ...(claimed.last_error === null ? {} : { lastError: claimed.last_error }),
      };
    },

    async markNotified(squad, weekStart) {
      const marked = await db
        .updateTable('weekly_awards')
        .set({ notified_at: sql`now()` })
        .where('squad_id', '=', squad)
        .where('week_start', '=', weekStart)
        .where('notified_at', 'is', null)
        .where('given_at', 'is not', null)
        .returning('squad_id')
        .executeTakeFirst();
      return marked !== undefined;
    },
  };
}
