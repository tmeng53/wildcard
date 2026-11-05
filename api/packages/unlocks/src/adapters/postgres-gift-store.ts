import type { Kysely } from 'kysely';

import { CoachId, type CoachGift } from '../domain/gifts.js';
import { PieceId } from '../domain/unlocks.js';
import type { GiftStore } from '../ports.js';
import type { DB } from './tables.js';

/**
 * The gift pool and members' gifts on Postgres (`supabase/migrations`, `gift_pieces` and
 * `coach_gifts`). A trigger logs each change to the pool; a gift row is its own log.
 */
export function createPostgresGiftStore(db: Kysely<DB>): GiftStore {
  const shown = (row: {
    piece_id: string;
    coach_id: string;
    squad_id: string;
    given_at: Date | string;
  }): CoachGift => ({
    piece: PieceId.parse(row.piece_id),
    coach: CoachId.parse(row.coach_id),
    squad: row.squad_id,
    givenAt: new Date(row.given_at),
  });
  return {
    async pieces() {
      const rows = await db.selectFrom('gift_pieces').selectAll().orderBy('piece_id').execute();
      return rows.map((row) => ({ id: PieceId.parse(row.piece_id), offered: row.offered }));
    },

    async putPiece({ id, offered }) {
      await db
        .insertInto('gift_pieces')
        .values({ piece_id: id, offered })
        .onConflict((conflict) => conflict.column('piece_id').doUpdateSet({ offered }))
        .execute();
    },

    async giftsOf(member) {
      const rows = await db
        .selectFrom('coach_gifts')
        .selectAll()
        .where('member_id', '=', member)
        .orderBy('given_at')
        .orderBy('piece_id')
        .execute();
      return rows.map(shown);
    },

    async give(member, { piece, coach, squad }) {
      const inserted = await db
        .insertInto('coach_gifts')
        .values({ member_id: member, piece_id: piece, coach_id: coach, squad_id: squad })
        .onConflict((conflict) => conflict.columns(['member_id', 'piece_id']).doNothing())
        .returningAll()
        .executeTakeFirst();
      if (inserted !== undefined) return { gift: shown(inserted), fresh: true };
      const kept = await db
        .selectFrom('coach_gifts')
        .selectAll()
        .where('member_id', '=', member)
        .where('piece_id', '=', piece)
        .executeTakeFirstOrThrow();
      return { gift: shown(kept), fresh: false };
    },
  };
}
