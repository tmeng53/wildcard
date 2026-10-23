import { sql, type Kysely } from 'kysely';

import { MemberId, NudgeKind, SquadId, type Nudge } from '../domain/nudge.js';
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

    async receivedBy({ member, since, until, kind }) {
      let query = selectNudges()
        .where('to_member_id', '=', member)
        .where('at', '>=', since)
        .where('at', '<', until);
      if (kind !== undefined) query = query.where('kind', '=', kind);
      const rows = await query.execute();
      return rows.map(toNudge);
    },

    async sentBy({ member, squad, day, kind }) {
      const rows = await selectNudges()
        .where('from_member_id', '=', member)
        .where('squad_id', '=', squad)
        .where('day', '=', day)
        .where('kind', '=', kind)
        .execute();
      return rows.map(toNudge);
    },
  };

  function selectNudges() {
    return db
      .selectFrom('nudges')
      .select([
        'from_member_id',
        'to_member_id',
        'squad_id',
        'kind',
        sql<string>`day::text`.as('day'),
        'at',
      ])
      .orderBy('at')
      .orderBy('id');
  }
}

function toNudge(row: {
  readonly from_member_id: string;
  readonly to_member_id: string;
  readonly squad_id: string;
  readonly kind: string;
  readonly day: string;
  readonly at: Date | string;
}): Nudge {
  return {
    from: MemberId.parse(row.from_member_id),
    to: MemberId.parse(row.to_member_id),
    squad: SquadId.parse(row.squad_id),
    kind: NudgeKind.parse(row.kind),
    day: row.day,
    at: new Date(row.at),
  };
}
