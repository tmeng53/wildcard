import { sql, type Kysely } from 'kysely';

import { MemberId, NudgeKind, SquadId } from '../domain/nudge.js';
import type { NudgeStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type NudgeTables = DB;

/** The nudge store on Postgres (`supabase/migrations`). */
export function createPostgresNudgeStore(db: Kysely<NudgeTables>): NudgeStore {
  return {
    async add({ from, to, squad, kind, day, at }) {
      // Two sends at once keep one nudge: the first one written.
      const inserted = await db
        .insertInto('nudges')
        .values({ from_member_id: from, to_member_id: to, squad_id: squad, kind, day, at })
        .onConflict((conflict) =>
          conflict.columns(['from_member_id', 'to_member_id', 'kind', 'day']).doNothing(),
        )
        .returning('id')
        .executeTakeFirst();
      return inserted === undefined ? 'unchanged' : 'created';
    },

    async receivedBy({ member, since, until }) {
      const rows = await db
        .selectFrom('nudges')
        .select([
          'from_member_id',
          'to_member_id',
          'squad_id',
          'kind',
          sql<string>`day::text`.as('day'),
          'at',
        ])
        .where('to_member_id', '=', member)
        .where('at', '>=', since)
        .where('at', '<', until)
        .orderBy('at')
        .orderBy('id')
        .execute();
      return rows.map((row) => ({
        from: MemberId.parse(row.from_member_id),
        to: MemberId.parse(row.to_member_id),
        squad: SquadId.parse(row.squad_id),
        kind: NudgeKind.parse(row.kind),
        day: row.day,
        at: new Date(row.at),
      }));
    },
  };
}
