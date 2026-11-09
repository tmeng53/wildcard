import { sql, type Kysely } from 'kysely';
import { z } from 'zod';

import {
  BadgeNames,
  EventName,
  GivenKind,
  type Badge,
  type Given,
  type HeldBadge,
  type TeamPiece,
  type Voucher,
} from '../domain/rewards.js';
import { PieceId } from '../domain/unlocks.js';
import type { RewardStore } from '../ports.js';
import type { DB } from './tables.js';

/** A badge's words as stored, with their own `version`. */
const StoredNames = BadgeNames.extend({ version: z.literal(1) }).transform(
  (stored): BadgeNames => ({
    'zh-Hans': stored['zh-Hans'],
    'zh-Hant': stored['zh-Hant'],
    en: stored.en,
  }),
);

/**
 * Badges, vouchers and what the team and events give on Postgres (`supabase/migrations`): the
 * catalogs `badges` and `vouchers` (logged to `reward_catalog_events`), `event` and `team` rows of
 * `reward_triggers` and their `grants`, which are their own log.
 */
export function createPostgresRewardStore(db: Kysely<DB>): RewardStore {
  // A reward row stays once added, so it needs no transaction with what names it (and the caller
  // may already hold one).
  const addReward = (reward: Given) =>
    db
      .insertInto('rewards')
      .values(reward)
      .onConflict((conflict) => conflict.columns(['kind', 'id']).doNothing())
      .execute();

  return {
    async badges() {
      const rows = await db.selectFrom('badges').selectAll().orderBy('id').execute();
      return rows.map(badgeOf);
    },

    async putBadge({ id, names, glyph, tone, offered }) {
      await addReward({ kind: 'badge', id });
      const changed = { names: JSON.stringify({ version: 1, ...names }), glyph, tone, offered };
      await db
        .insertInto('badges')
        .values({ id, ...changed })
        .onConflict((conflict) => conflict.column('id').doUpdateSet(changed))
        .execute();
    },

    async vouchers() {
      const rows = await db.selectFrom('vouchers').selectAll().orderBy('id').execute();
      return rows.map((row): Voucher => ({
        id: row.id,
        premiumDays: row.premium_days,
        offered: row.offered,
      }));
    },

    async putVoucher({ id, premiumDays, offered }) {
      await addReward({ kind: 'voucher', id });
      const changed = { premium_days: premiumDays, offered };
      await db
        .insertInto('vouchers')
        .values({ id, ...changed })
        .onConflict((conflict) => conflict.column('id').doUpdateSet(changed))
        .execute();
    },

    async exists({ kind, id }) {
      const row = await db
        .selectFrom('rewards')
        .select('id')
        .where('kind', '=', kind)
        .where('id', '=', id)
        .executeTakeFirst();
      return row !== undefined;
    },

    async putTrigger(edit) {
      // A piece is named by its art alone; a badge or voucher is in its catalog first.
      if (edit.kind === 'piece') await addReward({ kind: 'piece', id: edit.id });
      const changed = {
        offered: edit.offered,
        events: edit.way === 'event' && edit.events !== undefined ? [...edit.events] : null,
      };
      await db
        .insertInto('reward_triggers')
        .values({ reward_kind: edit.kind, reward_id: edit.id, kind: edit.way, ...changed })
        .onConflict((conflict) =>
          conflict.columns(['reward_kind', 'reward_id', 'kind']).doUpdateSet(changed),
        )
        .execute();
    },

    async givenBy(event) {
      const rows = await db
        .selectFrom('reward_triggers')
        .select(['reward_kind', 'reward_id'])
        .where('kind', '=', 'event')
        .where('offered', '=', true)
        .where(sql<boolean>`${event} = any(events)`)
        .orderBy('reward_kind')
        .orderBy('reward_id')
        .execute();
      return rows.map(givenOf);
    },

    async teamGives({ kind, id }) {
      const row = await db
        .selectFrom('reward_triggers')
        .select('offered')
        .where('reward_kind', '=', kind)
        .where('reward_id', '=', id)
        .where('kind', '=', 'team')
        .executeTakeFirst();
      return row?.offered ?? false;
    },

    async grantFor(occurrence, rewards) {
      const kept: Given[] = [];
      // One by one, since a piece is held once whatever gave it, and a badge or voucher once an
      // occurrence: each has its own unique index.
      for (const reward of rewards) {
        const values = {
          member_id: occurrence.member,
          reward_kind: reward.kind,
          reward_id: reward.id,
          via: 'event',
          event: occurrence.event,
          event_id: occurrence.id,
          at: occurrence.at.toISOString(),
        };
        const inserted =
          reward.kind === 'piece'
            ? await db
                .insertInto('grants')
                .values(values)
                .onConflict((conflict) =>
                  conflict
                    .columns(['member_id', 'reward_kind', 'reward_id'])
                    .where('reward_kind', 'in', ['store', 'prop', 'piece'])
                    .doNothing(),
                )
                .returning('id')
                .executeTakeFirst()
            : await db
                .insertInto('grants')
                .values(values)
                .onConflict((conflict) =>
                  conflict
                    .columns(['member_id', 'reward_kind', 'reward_id', 'event', 'event_id'])
                    .where('via', '=', 'event')
                    .doNothing(),
                )
                .returning('id')
                .executeTakeFirst();
        if (inserted !== undefined) kept.push(reward);
      }
      return kept;
    },

    async grantByTeam({ member, reward, admin, at }) {
      const values = {
        member_id: member,
        reward_kind: reward.kind,
        reward_id: reward.id,
        via: 'team',
        admin_id: admin,
        at: at.toISOString(),
      };
      // A piece is held once; each badge or voucher the team gives is one more.
      const inserted =
        reward.kind === 'piece'
          ? await db
              .insertInto('grants')
              .values(values)
              .onConflict((conflict) =>
                conflict
                  .columns(['member_id', 'reward_kind', 'reward_id'])
                  .where('reward_kind', 'in', ['store', 'prop', 'piece'])
                  .doNothing(),
              )
              .returning('id')
              .executeTakeFirst()
          : await db.insertInto('grants').values(values).returning('id').executeTakeFirst();
      return inserted !== undefined;
    },

    async badgesOf(member) {
      const rows = await db
        .selectFrom('grants')
        .innerJoin('badges', 'badges.id', 'grants.reward_id')
        .select([
          'badges.id',
          'badges.names',
          'badges.glyph',
          'badges.tone',
          'badges.offered',
          sql<number>`count(*)::int`.as('times'),
          sql<Date | string>`max(grants.at)`.as('latest_at'),
        ])
        .where('grants.member_id', '=', member)
        .where('grants.reward_kind', '=', 'badge')
        .groupBy(['badges.id', 'badges.names', 'badges.glyph', 'badges.tone', 'badges.offered'])
        .orderBy('latest_at', 'desc')
        .orderBy('badges.id')
        .execute();
      return rows.map((row): HeldBadge => ({
        badge: badgeOf(row),
        times: row.times,
        latestAt: new Date(row.latest_at),
      }));
    },

    async teamPiecesOf(member) {
      // A piece an event gave, or one an admin gave by its `team` trigger (give_unlocks' grants
      // carry the rule they stood for, and show as unlocks).
      const rows = await db
        .selectFrom('grants')
        .select(['reward_id', 'event', 'at'])
        .where('member_id', '=', member)
        .where('reward_kind', '=', 'piece')
        .where((where) =>
          where.or([
            where('via', '=', 'event'),
            where.and([where('via', '=', 'team'), where('after', 'is', null)]),
          ]),
        )
        .orderBy('at')
        .orderBy('reward_id')
        .execute();
      return rows.map((row): TeamPiece => ({
        piece: PieceId.parse(row.reward_id),
        givenAt: new Date(row.at),
        ...(row.event === null ? {} : { event: EventName.parse(row.event) }),
      }));
    },
  };
}

function badgeOf(row: {
  id: string;
  names: unknown;
  glyph: string;
  tone: string;
  offered: boolean;
}): Badge {
  return {
    id: row.id,
    names: StoredNames.parse(row.names),
    glyph: row.glyph,
    tone: row.tone,
    offered: row.offered,
  };
}

function givenOf(row: { reward_kind: string; reward_id: string }): Given {
  return { kind: GivenKind.parse(row.reward_kind), id: row.reward_id };
}
