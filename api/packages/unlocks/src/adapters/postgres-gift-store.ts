import type { Kysely } from 'kysely';

import { CoachId, GivenBy, type CoachGift } from '../domain/gifts.js';
import { PieceId } from '../domain/unlocks.js';
import type { GiftStore } from '../ports.js';
import type { DB } from './tables.js';

/**
 * The gift pool and members' gifts on Postgres (`supabase/migrations`): a piece in the pool is a
 * reward with a `coach` trigger (`rewards`, `reward_triggers`), a gift a `coach` grant (`grants`)
 * and its opening a `grant_opens` row. A trigger logs each change to the pool; a grant and its
 * opening are their own log.
 */
export function createPostgresGiftStore(db: Kysely<DB>): GiftStore {
  const shown = (row: {
    reward_id: string;
    coach_id: string | null;
    squad_id: string | null;
    at: Date | string;
    line: string | null;
    given_by: string | null;
    opened_at?: Date | string | null;
    worn?: boolean | null;
  }): CoachGift => {
    if (row.coach_id === null || row.squad_id === null) {
      throw new Error('a coach grant without its coach or squad');
    }
    return {
      piece: PieceId.parse(row.reward_id),
      coach: CoachId.parse(row.coach_id),
      squad: row.squad_id,
      givenAt: new Date(row.at),
      givenBy: GivenBy.parse(row.given_by),
      ...(row.line === null ? {} : { line: row.line }),
      ...(row.opened_at === null || row.opened_at === undefined
        ? {}
        : { opened: { at: new Date(row.opened_at), worn: row.worn === true } }),
    };
  };
  const coachGrants = (member: string) =>
    db
      .selectFrom('grants as g')
      .leftJoin('grant_opens as o', 'o.grant_id', 'g.id')
      .select([
        'g.id',
        'g.reward_id',
        'g.coach_id',
        'g.squad_id',
        'g.at',
        'g.line',
        'g.given_by',
        'o.at as opened_at',
        'o.worn',
      ])
      .where('g.member_id', '=', member)
      .where('g.via', '=', 'coach');
  return {
    async pieces() {
      const rows = await db
        .selectFrom('reward_triggers')
        .select(['reward_id', 'offered', 'description'])
        .where('kind', '=', 'coach')
        .where('reward_kind', '=', 'piece')
        .orderBy('reward_id')
        .execute();
      return rows.map((row) => ({
        id: PieceId.parse(row.reward_id),
        offered: row.offered,
        ...(row.description === null ? {} : { description: row.description }),
      }));
    },

    async putPiece({ id, offered, description }) {
      const changed = { offered, ...(description === undefined ? {} : { description }) };
      // A reward row stays once added, so it needs no transaction with its trigger (and the
      // caller may already hold one).
      await db
        .insertInto('rewards')
        .values({ kind: 'piece', id })
        .onConflict((conflict) => conflict.columns(['kind', 'id']).doNothing())
        .execute();
      await db
        .insertInto('reward_triggers')
        .values({ reward_kind: 'piece', reward_id: id, kind: 'coach', ...changed })
        .onConflict((conflict) =>
          conflict.columns(['reward_kind', 'reward_id', 'kind']).doUpdateSet(changed),
        )
        .execute();
    },

    async giftsOf(member) {
      const rows = await coachGrants(member).orderBy('g.at').orderBy('g.reward_id').execute();
      return rows.map(shown);
    },

    async give(member, { piece, coach, squad, line, givenBy, admin, weekStart }) {
      const inserted = await db
        .insertInto('grants')
        .values({
          member_id: member,
          reward_kind: 'piece',
          reward_id: piece,
          via: 'coach',
          coach_id: coach,
          squad_id: squad,
          line: line ?? null,
          given_by: givenBy,
          admin_id: admin ?? null,
          week_from: weekStart.toISOString(),
          at: new Date().toISOString(),
        })
        // Either the piece or the week: the caller reads which.
        .onConflict((conflict) => conflict.doNothing())
        .returningAll()
        .executeTakeFirst();
      return inserted === undefined ? undefined : shown(inserted);
    },

    async open({ member, piece, worn }) {
      const given = await coachGrants(member).where('g.reward_id', '=', piece).executeTakeFirst();
      if (given === undefined) return false;
      await db
        .insertInto('grant_opens')
        .values({ grant_id: given.id, worn })
        .onConflict((conflict) => conflict.column('grant_id').doNothing())
        .execute();
      return true;
    },
  };
}
