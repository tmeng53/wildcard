import type { Kysely } from 'kysely';

import { BroadcastId, BroadcastValue, type Broadcast } from '../domain/broadcast.js';
import type { BroadcastStore } from '../ports.js';
import type { DB } from './tables.js';

/** The broadcast store on Postgres (`supabase/migrations`): every save a row, the newest wins. */
export function createPostgresBroadcastStore(db: Kysely<DB>): BroadcastStore {
  const current = () =>
    db
      .selectFrom('broadcasts')
      .select(['broadcast_id', 'broadcast', 'changed_by', 'at', 'id'])
      .distinctOn('broadcast_id')
      .orderBy('broadcast_id')
      .orderBy('id', 'desc');
  const read = (row: {
    readonly broadcast_id: string;
    readonly broadcast: unknown;
    readonly changed_by: string | null;
    readonly at: Date | string;
  }): Broadcast[] => {
    // A shape this build no longer reads is left out, never an error.
    const value = BroadcastValue.safeParse(row.broadcast);
    if (!value.success) return [];
    return [
      {
        id: BroadcastId.parse(row.broadcast_id),
        value: value.data,
        by: row.changed_by,
        savedAt: new Date(row.at),
      },
    ];
  };
  return {
    async put({ id, value, by }) {
      await db
        .insertInto('broadcasts')
        .values({ broadcast_id: id, broadcast: JSON.stringify(value), changed_by: by })
        .execute();
    },

    async all() {
      const rows = await db
        .selectFrom(current().as('current'))
        .selectAll()
        .orderBy('id', 'desc')
        .execute();
      return rows.flatMap(read);
    },

    async byId(ids) {
      if (ids.length === 0) return [];
      const rows = await current()
        .where('broadcast_id', 'in', [...new Set(ids)])
        .execute();
      return rows.flatMap(read);
    },
  };
}
