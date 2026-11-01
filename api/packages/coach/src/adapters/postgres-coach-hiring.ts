import { hasErrorCode } from '@wildcard/errors';
import { sql, type Kysely } from 'kysely';

import { CoachId } from '../domain/coach.js';
import { SquadId } from '../domain/settings.js';
import type { CoachHiringStore } from '../ports.js';
import type { DB } from './tables.js';

/** Postgres's code for a reference to a row that isn't there: here, the squad. */
const FOREIGN_KEY_VIOLATION = '23503';

/** Each squad's coach on Postgres, every hire and firing logged (`supabase/migrations`). */
export function createPostgresCoachHiring(db: Kysely<DB>): CoachHiringStore {
  return {
    async coachOf(squad) {
      const row = await db
        .selectFrom('squad_coaches')
        .select(['coach_id', 'hired_at'])
        .where('squad_id', '=', squad)
        .executeTakeFirst();
      return row === undefined
        ? undefined
        : { coach: CoachId.parse(row.coach_id), since: new Date(row.hired_at) };
    },

    async hired() {
      const rows = await db.selectFrom('squad_coaches').select(['squad_id', 'coach_id']).execute();
      return new Map(
        rows.map(({ squad_id, coach_id }) => [SquadId.parse(squad_id), CoachId.parse(coach_id)]),
      );
    },

    async hire({ squad, coach, by }) {
      try {
        // One statement: the hire and its log row, only when the squad had no coach.
        const hired = await db
          .with('hire', (cte) =>
            cte
              .insertInto('squad_coaches')
              .values({ squad_id: squad, coach_id: coach, hired_by: by })
              .onConflict((conflict) => conflict.column('squad_id').doNothing())
              .returning(['squad_id', 'coach_id']),
          )
          .insertInto('squad_coach_events')
          .columns(['squad_id', 'kind', 'coach_id', 'changed_by'])
          .expression((eb) =>
            eb
              .selectFrom('hire')
              .select([
                'hire.squad_id',
                sql<string>`'hired'`.as('kind'),
                'hire.coach_id',
                sql<string>`${by}::uuid`.as('changed_by'),
              ]),
          )
          .returning('id')
          .execute();
        return hired.length > 0 ? 'hired' : 'hasCoach';
      } catch (error) {
        if (hasErrorCode(error, FOREIGN_KEY_VIOLATION)) return 'noSquad';
        throw error;
      }
    },

    async fire({ squad, by }) {
      const fired = await db
        .with('fire', (cte) =>
          cte
            .deleteFrom('squad_coaches')
            .where('squad_id', '=', squad)
            .returning(['squad_id', 'coach_id']),
        )
        .insertInto('squad_coach_events')
        .columns(['squad_id', 'kind', 'coach_id', 'changed_by'])
        .expression((eb) =>
          eb
            .selectFrom('fire')
            .select([
              'fire.squad_id',
              sql<string>`'fired'`.as('kind'),
              'fire.coach_id',
              sql<string>`${by}::uuid`.as('changed_by'),
            ]),
        )
        .returning('coach_id')
        .execute();
      const [row] = fired;
      return row === undefined ? undefined : CoachId.parse(row.coach_id);
    },

    async replace({ squad, coach, by }) {
      const change = async (trx: Kysely<DB>): Promise<'hired' | 'same' | 'noSquad'> => {
        // The squad's coach row, locked, so a second change waits for this one.
        const current = await trx
          .selectFrom('squad_coaches')
          .select('coach_id')
          .where('squad_id', '=', squad)
          .forUpdate()
          .executeTakeFirst();
        if (current?.coach_id === coach) return 'same';
        const inTransaction = createPostgresCoachHiring(trx);
        if (current !== undefined) await inTransaction.fire({ squad, by });
        const hired = await inTransaction.hire({ squad, coach, by });
        if (hired === 'noSquad') return 'noSquad';
        // Another change got in first (two at once): this one keeps what it found.
        return hired === 'hired' ? 'hired' : 'same';
      };
      // Inside a caller's transaction already (the admin tools, tests), it runs in that one.
      return db.isTransaction ? change(db) : db.transaction().execute(change);
    },
  };
}
