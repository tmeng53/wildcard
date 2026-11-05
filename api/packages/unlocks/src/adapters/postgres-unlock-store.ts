import { SportId } from '@wildcard/sport-ids';
import type { Kysely } from 'kysely';

import {
  MemberId,
  SLOTS,
  UnlockKind,
  idFits,
  type Piece,
  type Store,
  type Unlock,
  type UnlockRule,
} from '../domain/unlocks.js';
import type { UnlockStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads, as generated from the migrations. */
export type UnlockTables = DB;

/**
 * The rules and members' unlocks on Postgres (`supabase/migrations`, `unlock_rules`,
 * `member_unlocks`, `stores` and `pieces`). Triggers log each rule, store and piece that changes;
 * an unlock row is its own log.
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
        id: itemId(row),
        sports: row.sports.map((sport) => SportId.parse(sport)),
        after: row.after,
        countsFrom: new Date(row.counts_from),
      }));
    },

    async putRule({ kind, id, sports, after }) {
      const changed = { sports: [...sports], after };
      await db
        .insertInto('unlock_rules')
        .values({ kind, item_id: id, ...changed })
        .onConflict((conflict) => conflict.columns(['kind', 'item_id']).doUpdateSet(changed))
        .execute();
    },

    async stores() {
      const rows = await db.selectFrom('stores').selectAll().orderBy('position').execute();
      return rows.map((row): Store => ({
        id: row.id,
        position: row.position,
        offered: row.offered,
        ...(row.switch_id === null ? {} : { switchId: row.switch_id }),
      }));
    },

    async pieces() {
      const rows = await db.selectFrom('pieces').selectAll().orderBy('id').execute();
      return rows.map((row): Piece => ({
        id: row.id,
        storeId: row.store_id,
        slot: slot(row.slot),
        starter: row.starter,
        offered: row.offered,
        ...(row.switch_id === null ? {} : { switchId: row.switch_id }),
      }));
    },

    async putStore({ id, ...edit }) {
      const changed = { position: edit.position, switch_id: edit.switchId, offered: edit.offered };
      await db
        .insertInto('stores')
        .values({ id, ...changed })
        .onConflict((conflict) => conflict.column('id').doUpdateSet(changed))
        .execute();
    },

    async putPiece({ id, ...edit }) {
      const changed = {
        store_id: edit.storeId,
        slot: edit.slot,
        starter: edit.starter,
        switch_id: edit.switchId,
        offered: edit.offered,
      };
      await db
        .insertInto('pieces')
        .values({ id, ...changed })
        .onConflict((conflict) => conflict.column('id').doUpdateSet(changed))
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
        id: itemId(row),
        sports: row.sports.map((sport) => SportId.parse(sport)),
        after: row.after,
        by: unlockedBy(row),
        unlockedAt: new Date(row.unlocked_at),
      }));
    },

    async grant(member, unlocks) {
      if (unlocks.length === 0) return [];
      const inserted = await db
        .insertInto('member_unlocks')
        .values(
          unlocks.map((unlock) => ({
            member_id: member,
            kind: unlock.kind,
            item_id: unlock.id,
            sports: [...unlock.sports],
            after: unlock.after,
            check_in_id: 'checkIn' in unlock.by ? unlock.by.checkIn : null,
            given_by: 'admin' in unlock.by ? unlock.by.admin : null,
            unlocked_at: unlock.unlockedAt.toISOString(),
          })),
        )
        .onConflict((conflict) => conflict.columns(['member_id', 'kind', 'item_id']).doNothing())
        .returning(['kind', 'item_id'])
        .execute();
      const fresh = new Set(inserted.map(({ kind, item_id }) => `${kind}:${item_id}`));
      return unlocks.filter(({ kind, id }) => fresh.has(`${kind}:${id}`));
    },
  };
}

/** A row's id, checked against its kind's shape (the database checks it too). */
function itemId(row: { kind: string; item_id: string }): string {
  if (!idFits(UnlockKind.parse(row.kind), row.item_id)) {
    throw new Error(`${row.item_id} is not a ${row.kind} id`);
  }
  return row.item_id;
}

/** A row's slot, which the database checks too. */
function slot(value: string): Piece['slot'] {
  const found = SLOTS.find((known) => known === value);
  if (found === undefined) throw new Error(`${value} is not a slot`);
  return found;
}

/** A row's check-in, or else its giver: the table holds exactly one of them. */
function unlockedBy(row: { check_in_id: string | null; given_by: string | null }): Unlock['by'] {
  if (row.check_in_id !== null) return { checkIn: row.check_in_id };
  return { admin: MemberId.parse(row.given_by) };
}
