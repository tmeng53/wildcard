import { SportId } from '@wildcard/sport-ids';
import { sql, type Kysely } from 'kysely';

import {
  MemberId,
  PieceId,
  SLOTS,
  UnlockKind,
  idFits,
  type Claim,
  type Piece,
  type Store,
  type Unlock,
  type UnlockRule,
} from '../domain/unlocks.js';
import type { Trigger } from '../domain/rewards.js';
import type { UnlockStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads, as generated from the migrations. */
export type UnlockTables = DB;

/**
 * The rules and members' unlocks on Postgres (`supabase/migrations`): a rule is a reward's
 * `training` trigger (`rewards`, `reward_triggers`), an unlock a `training` or `team` grant
 * (`grants`), with `stores` and `pieces`. Triggers log each trigger, store and piece that changes;
 * a grant row is its own log.
 */
export function createPostgresUnlockStore(db: Kysely<UnlockTables>): UnlockStore {
  return {
    async rewards() {
      const [rewards, triggers] = await Promise.all([
        db.selectFrom('rewards').select(['kind', 'id']).orderBy('kind').orderBy('id').execute(),
        db.selectFrom('reward_triggers').selectAll().orderBy('kind').execute(),
      ]);
      return rewards.map(({ kind, id }) => ({
        kind: UnlockKind.parse(kind),
        id: itemId({ kind, item_id: id }),
        triggers: triggers
          .filter((row) => row.reward_kind === kind && row.reward_id === id)
          .map(triggerOf),
      }));
    },

    async rules() {
      const rows = await db
        .selectFrom('reward_triggers')
        .select(['reward_kind', 'reward_id', 'sports', 'after', 'counts_from'])
        .where('kind', '=', 'training')
        .where('offered', '=', true)
        .orderBy('reward_kind')
        .orderBy('reward_id')
        .execute();
      return rows.map((row): UnlockRule => ({
        kind: UnlockKind.parse(row.reward_kind),
        id: itemId({ kind: row.reward_kind, item_id: row.reward_id }),
        sports: (row.sports ?? []).map((sport) => SportId.parse(sport)),
        after: trainingAfter(row.after),
        countsFrom: new Date(trainingStart(row.counts_from)),
      }));
    },

    async putRule({ kind, id, sports, after }) {
      // Putting a retired rule again brings it back.
      const changed = { sports: [...sports], after, offered: true };
      // A reward row stays once added, so it needs no transaction with its trigger (and the
      // caller may already hold one).
      await db
        .insertInto('rewards')
        .values({ kind, id })
        .onConflict((conflict) => conflict.columns(['kind', 'id']).doNothing())
        .execute();
      await db
        .insertInto('reward_triggers')
        .values({
          reward_kind: kind,
          reward_id: id,
          kind: 'training',
          ...changed,
          counts_from: sql<Date>`now()`,
        })
        .onConflict((conflict) =>
          conflict.columns(['reward_kind', 'reward_id', 'kind']).doUpdateSet(changed),
        )
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
      // The grants of rewards with a rule: earned by training, or given by the team. A coach's
      // gifts are the gift store's.
      const rows = await db
        .selectFrom('grants')
        .select([
          'reward_kind',
          'reward_id',
          'sports',
          'after',
          'check_in_id',
          'admin_id',
          'via',
          'at',
        ])
        .where('member_id', '=', member)
        .where('via', 'in', ['training', 'team'])
        .where('after', 'is not', null)
        .orderBy('at')
        .orderBy('reward_kind')
        .orderBy('reward_id')
        .execute();
      return rows.map((row) => ({
        kind: UnlockKind.parse(row.reward_kind),
        id: itemId({ kind: row.reward_kind, item_id: row.reward_id }),
        sports: (row.sports ?? []).map((sport) => SportId.parse(sport)),
        after: trainingAfter(row.after),
        by: unlockedBy(row),
        unlockedAt: new Date(row.at),
      }));
    },

    async grant(member, unlocks) {
      if (unlocks.length === 0) return [];
      const inserted = await db
        .insertInto('grants')
        .values(
          unlocks.map((unlock) => ({
            member_id: member,
            reward_kind: unlock.kind,
            reward_id: unlock.id,
            via: 'checkIn' in unlock.by ? 'training' : 'team',
            sports: [...unlock.sports],
            after: unlock.after,
            check_in_id: 'checkIn' in unlock.by ? unlock.by.checkIn : null,
            admin_id: 'admin' in unlock.by ? unlock.by.admin : null,
            at: unlock.unlockedAt.toISOString(),
          })),
        )
        .onConflict((conflict) =>
          conflict.columns(['member_id', 'reward_kind', 'reward_id']).doNothing(),
        )
        .returning(['reward_kind', 'reward_id'])
        .execute();
      const fresh = new Set(
        inserted.map(({ reward_kind, reward_id }) => `${reward_kind}:${reward_id}`),
      );
      return unlocks.filter(({ kind, id }) => fresh.has(`${kind}:${id}`));
    },

    async claimsOf(member) {
      const rows = await db
        .selectFrom('piece_claims')
        .select(['piece_id', 'claimed_at'])
        .where('member_id', '=', member)
        .orderBy('claimed_at')
        .orderBy('piece_id')
        .execute();
      return rows.map(claimOf);
    },

    async claim(member, piece) {
      await db
        .insertInto('piece_claims')
        .values({ member_id: member, piece_id: piece })
        .onConflict((conflict) => conflict.columns(['member_id', 'piece_id']).doNothing())
        .execute();
      const kept = await db
        .selectFrom('piece_claims')
        .select(['piece_id', 'claimed_at'])
        .where('member_id', '=', member)
        .where('piece_id', '=', piece)
        .executeTakeFirstOrThrow();
      return claimOf(kept);
    },
  };
}

function claimOf(row: { piece_id: string; claimed_at: Date | string }): Claim {
  return { piece: PieceId.parse(row.piece_id), claimedAt: new Date(row.claimed_at) };
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

/** A grant's check-in, or else the team's admin who gave it: the table holds one of them. */
function unlockedBy(row: {
  via: string;
  check_in_id: string | null;
  admin_id: string | null;
}): Unlock['by'] {
  if (row.via === 'training' && row.check_in_id !== null) return { checkIn: row.check_in_id };
  return { admin: MemberId.parse(row.admin_id) };
}

/** A trigger row as the way it is. */
function triggerOf(row: {
  kind: string;
  offered: boolean;
  sports: string[] | null;
  after: number | null;
  counts_from: Date | string | null;
  description: string | null;
}): Trigger {
  switch (row.kind) {
    case 'training':
      return {
        kind: 'training',
        offered: row.offered,
        sports: (row.sports ?? []).map((sport) => SportId.parse(sport)),
        after: trainingAfter(row.after),
        countsFrom: new Date(trainingStart(row.counts_from)),
      };
    case 'coach':
      return {
        kind: 'coach',
        offered: row.offered,
        ...(row.description === null ? {} : { description: row.description }),
      };
    case 'team':
      return { kind: 'team', offered: row.offered };
    default:
      throw new Error(`${row.kind} is not a way to get a reward`);
  }
}

/** A training trigger's or its grant's `after`, which the database holds for every one. */
function trainingAfter(after: number | null): number {
  if (after === null) throw new Error('a training trigger without its count');
  return after;
}

/** A training trigger's start, which the database holds for every one. */
function trainingStart(at: Date | string | null): Date | string {
  if (at === null) throw new Error('a training trigger without its start');
  return at;
}
