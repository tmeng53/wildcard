import { sql, type Kysely } from 'kysely';

import { CoachId } from '../domain/coach.js';
import type { CoachLetter } from '../domain/letter.js';
import { SquadId } from '../domain/settings.js';
import type { CoachLetterStore } from '../ports.js';
import type { DB } from './tables.js';

/**
 * The letter written for a change of coach, by its hire, or the one the squad's coach now was
 * left when it took over; with both coaches as the app draws them.
 */
export async function letterWhere(
  db: Kysely<DB>,
  which: { readonly hireEvent: number } | { readonly toCoachNowOf: string },
): Promise<CoachLetter | undefined> {
  const letters = db.selectFrom('coach_letters');
  const narrowed =
    'hireEvent' in which
      ? letters.where('coach_letters.hire_event_id', '=', String(which.hireEvent))
      : letters.where((eb) =>
          eb.exists(
            // Written for the hire that made the coach now: not for a time it coached the squad
            // before, nor for a change the squad has since made again.
            eb
              .selectFrom('squad_coaches')
              .innerJoin('squad_coach_events as hire', (join) =>
                join
                  .onRef('hire.squad_id', '=', 'squad_coaches.squad_id')
                  .onRef('hire.coach_id', '=', 'squad_coaches.coach_id')
                  .onRef('hire.at', '=', 'squad_coaches.hired_at')
                  .on('hire.kind', '=', 'hired'),
              )
              .select('hire.id')
              .where('squad_coaches.squad_id', '=', which.toCoachNowOf)
              .whereRef('hire.id', '=', 'coach_letters.hire_event_id'),
          ),
        );
  const row = await narrowed
    .innerJoin('coaches as from_coach', 'from_coach.id', 'coach_letters.from_coach')
    .innerJoin('coaches as to_coach', 'to_coach.id', 'coach_letters.to_coach')
    .select([
      'coach_letters.id',
      'coach_letters.squad_id',
      sql<string>`to_char(coach_letters.day, 'YYYY-MM-DD')`.as('day'),
      'coach_letters.text',
      'coach_letters.at',
      'from_coach.id as from_id',
      'from_coach.name as from_name',
      'from_coach.look as from_look',
      'to_coach.id as to_id',
      'to_coach.name as to_name',
      'to_coach.look as to_look',
    ])
    .orderBy('coach_letters.id', 'desc')
    .limit(1)
    .executeTakeFirst();
  return row === undefined
    ? undefined
    : {
        id: Number(row.id),
        squad: SquadId.parse(row.squad_id),
        from: { id: row.from_id, name: row.from_name, look: row.from_look },
        to: { id: row.to_id, name: row.to_name, look: row.to_look },
        day: row.day,
        text: row.text,
        at: new Date(row.at),
      };
}

/** Coaches' letters to the next one on Postgres (`supabase/migrations`). */
export function createPostgresCoachLetters(db: Kysely<DB>): CoachLetterStore {
  return {
    async handover(squad) {
      // The coach now's hire, and the firing made with it in the same step (换教练): the same
      // moment, just before it in the log.
      const row = await db
        .selectFrom('squad_coaches')
        .innerJoin('squad_coach_events as hire', (join) =>
          join
            .onRef('hire.squad_id', '=', 'squad_coaches.squad_id')
            .onRef('hire.coach_id', '=', 'squad_coaches.coach_id')
            .onRef('hire.at', '=', 'squad_coaches.hired_at')
            .on('hire.kind', '=', 'hired'),
        )
        .innerJoin('squad_coach_events as fire', (join) =>
          join
            .onRef('fire.squad_id', '=', 'hire.squad_id')
            .onRef('fire.at', '=', 'hire.at')
            .onRef('fire.id', '<', 'hire.id')
            .on('fire.kind', '=', 'fired'),
        )
        .select(['hire.id', 'hire.coach_id as to', 'fire.coach_id as from', 'hire.at'])
        .where('squad_coaches.squad_id', '=', squad)
        .orderBy('hire.id', 'desc')
        .orderBy('fire.id', 'desc')
        .executeTakeFirst();
      if (row === undefined || row.from === row.to) return undefined;
      return {
        hireEvent: Number(row.id),
        squad,
        from: CoachId.parse(row.from),
        to: CoachId.parse(row.to),
        at: new Date(row.at),
      };
    },

    async history(squad) {
      const rows = await db
        .selectFrom('squad_coach_events')
        .select(['kind', 'coach_id', 'at'])
        .where('squad_id', '=', squad)
        .orderBy('id')
        .execute();
      return rows.map(({ kind, coach_id, at }) => ({
        kind: kind === 'fired' ? ('fired' as const) : ('hired' as const),
        coach: CoachId.parse(coach_id),
        at: new Date(at),
      }));
    },

    async claim({ hireEvent, squad }) {
      const claimed = await db
        .insertInto('coach_letter_tries')
        .values({ hire_event_id: String(hireEvent), squad_id: squad })
        .onConflict((conflict) => conflict.column('hire_event_id').doNothing())
        .returning('hire_event_id')
        .execute();
      return claimed.length > 0;
    },

    async save({ handover, day, text }) {
      await db
        .insertInto('coach_letters')
        .values({
          squad_id: handover.squad,
          hire_event_id: String(handover.hireEvent),
          from_coach: handover.from,
          to_coach: handover.to,
          day,
          text,
        })
        .execute();
    },

    async ofHandover(hireEvent) {
      return letterWhere(db, { hireEvent });
    },
  };
}
