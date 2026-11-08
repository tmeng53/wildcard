import type { Kysely } from 'kysely';

import { CoachId, GivenBy, type CoachGift } from '../domain/gifts.js';
import { PieceId } from '../domain/unlocks.js';
import type { GiftStore } from '../ports.js';
import type { DB } from './tables.js';

/**
 * The gift pool and members' gifts on Postgres (`supabase/migrations`, `gift_pieces`,
 * `coach_gifts` and `coach_gift_opens`). A trigger logs each change to the pool; a gift row and
 * its opening are their own log.
 */
export function createPostgresGiftStore(db: Kysely<DB>): GiftStore {
  const shown = (row: {
    piece_id: string;
    coach_id: string;
    squad_id: string;
    given_at: Date | string;
    line: string | null;
    given_by: string;
    opened_at?: Date | string | null;
    worn?: boolean | null;
  }): CoachGift => ({
    piece: PieceId.parse(row.piece_id),
    coach: CoachId.parse(row.coach_id),
    squad: row.squad_id,
    givenAt: new Date(row.given_at),
    givenBy: GivenBy.parse(row.given_by),
    ...(row.line === null ? {} : { line: row.line }),
    ...(row.opened_at === null || row.opened_at === undefined
      ? {}
      : { opened: { at: new Date(row.opened_at), worn: row.worn === true } }),
  });
  return {
    async pieces() {
      const rows = await db.selectFrom('gift_pieces').selectAll().orderBy('piece_id').execute();
      return rows.map((row) => ({
        id: PieceId.parse(row.piece_id),
        offered: row.offered,
        ...(row.description === null ? {} : { description: row.description }),
      }));
    },

    async putPiece({ id, offered, description }) {
      await db
        .insertInto('gift_pieces')
        .values({ piece_id: id, offered, ...(description === undefined ? {} : { description }) })
        .onConflict((conflict) =>
          conflict
            .column('piece_id')
            .doUpdateSet({ offered, ...(description === undefined ? {} : { description }) }),
        )
        .execute();
    },

    async giftsOf(member) {
      const rows = await db
        .selectFrom('coach_gifts as g')
        .leftJoin('coach_gift_opens as o', (join) =>
          join.onRef('o.member_id', '=', 'g.member_id').onRef('o.piece_id', '=', 'g.piece_id'),
        )
        .select([
          'g.piece_id',
          'g.coach_id',
          'g.squad_id',
          'g.given_at',
          'g.line',
          'g.given_by',
          'o.at as opened_at',
          'o.worn',
        ])
        .where('g.member_id', '=', member)
        .orderBy('g.given_at')
        .orderBy('g.piece_id')
        .execute();
      return rows.map(shown);
    },

    async give(member, { piece, coach, squad, line, givenBy, admin, weekStart }) {
      const inserted = await db
        .insertInto('coach_gifts')
        .values({
          member_id: member,
          piece_id: piece,
          coach_id: coach,
          squad_id: squad,
          line: line ?? null,
          given_by: givenBy,
          admin_id: admin ?? null,
          week_from: weekStart.toISOString(),
        })
        // Either the piece or the week: the caller reads which.
        .onConflict((conflict) => conflict.doNothing())
        .returningAll()
        .executeTakeFirst();
      return inserted === undefined ? undefined : shown(inserted);
    },

    async open({ member, piece, worn }) {
      const given = await db
        .selectFrom('coach_gifts')
        .select('piece_id')
        .where('member_id', '=', member)
        .where('piece_id', '=', piece)
        .executeTakeFirst();
      if (given === undefined) return false;
      await db
        .insertInto('coach_gift_opens')
        .values({ member_id: member, piece_id: piece, worn })
        .onConflict((conflict) => conflict.columns(['member_id', 'piece_id']).doNothing())
        .execute();
      return true;
    },
  };
}
