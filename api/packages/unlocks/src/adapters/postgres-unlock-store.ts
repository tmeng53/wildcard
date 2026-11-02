import { SportId } from '@wildcard/sport-ids';
import type { Kysely } from 'kysely';

import { ItemId, UnlockKind, type UnlockRule } from '../domain/unlocks.js';
import type { UnlockStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads, as generated from the migrations. */
export type UnlockTables = DB;

/**
 * The rules and members' unlocks on Postgres (`supabase/migrations`, `unlock_rules` and
 * `member_unlocks`). A trigger logs each rule that changes; an unlock row is its own log.
 */
export function createPostgresUnlockStore(db: Kysely<UnlockTables>): UnlockStore {
  return {
    async rules() {
      const rows = await db
        .selectFrom('unlock_rules')
        .selectAll()
        .orderBy('kind')
        .orderBy('item_id')
        .execute();
      return rows.map((row): UnlockRule => ({
        kind: UnlockKind.parse(row.kind),
        id: ItemId.parse(row.item_id),
        sports: row.sports.map((sport) => SportId.parse(sport)),
        after: row.after,
        countsFrom: new Date(row.counts_from),
      }));
    },

    async putRule({ kind, id, sports, after }) {
      await db
        .insertInto('unlock_rules')
        .values({ kind, item_id: id, sports: [...sports], after })
        .onConflict((conflict) =>
          conflict.columns(['kind', 'item_id']).doUpdateSet({ sports: [...sports], after }),
        )
        .execute();
    },

    async unlocksOf(member) {
      const rows = await db
        .selectFrom('member_unlocks')
        .selectAll()
        .where('member_id', '=', member)
        .orderBy('unlocked_at')
        .orderBy('kind')
        .orderBy('item_id')
        .execute();
      return rows.map((row) => ({
        kind: UnlockKind.parse(row.kind),
        id: ItemId.parse(row.item_id),
        sports: row.sports.map((sport) => SportId.parse(sport)),
        after: row.after,
        checkIn: row.check_in_id,
        unlockedAt: new Date(row.unlocked_at),
      }));
    },

    async grant(member, unlocks) {
      if (unlocks.length === 0) return;
      await db
        .insertInto('member_unlocks')
        .values(
          unlocks.map((unlock) => ({
            member_id: member,
            kind: unlock.kind,
            item_id: unlock.id,
            sports: [...unlock.sports],
            after: unlock.after,
            check_in_id: unlock.checkIn,
            unlocked_at: unlock.unlockedAt.toISOString(),
          })),
        )
        .onConflict((conflict) => conflict.columns(['member_id', 'kind', 'item_id']).doNothing())
        .execute();
    },
  };
}
