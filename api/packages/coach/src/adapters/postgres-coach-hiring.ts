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
        .select('coach_id')
        .where('squad_id', '=', squad)
        .executeTakeFirst();
      return row === undefined ? undefined : CoachId.parse(row.coach_id);
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
        if (isForeignKeyViolation(error)) return 'noSquad';
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
  };
}

function isForeignKeyViolation(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === FOREIGN_KEY_VIOLATION
  );
}
