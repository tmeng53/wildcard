import { sql, type Kysely } from 'kysely';

import { CheckInId, MemberId, SquadId } from '../domain/check-in.js';
import { ReactionKind, type Reaction } from '../domain/reaction.js';
import type { ReactionStore } from '../ports.js';
import type { DB } from './tables.js';

const fromRow = (row: { member_id: string; kind: string; reacted_at: Date }): Reaction => ({
  member: MemberId.parse(row.member_id),
  kind: ReactionKind.parse(row.kind),
  reactedAt: row.reacted_at,
});

/** The reaction store on Postgres (`supabase/migrations`). */
export function createPostgresReactionStore(db: Kysely<DB>): ReactionStore {
  return {
    async save(checkIn, { member, kind, reactedAt }) {
      // One statement, so two reactions at once can't both count as new. The update runs only
      // for a different kind; `xmax = 0` tells a fresh row from an updated one.
      const row = await db
        .insertInto('check_in_reactions')
        .values({ check_in_id: checkIn, member_id: member, kind, reacted_at: reactedAt })
        .onConflict((conflict) =>
          conflict
            .columns(['check_in_id', 'member_id'])
            .doUpdateSet({ kind, reacted_at: reactedAt })
            .where('check_in_reactions.kind', '<>', kind),
        )
        .returning(sql<boolean>`xmax = 0`.as('created'))
        .executeTakeFirst();
      if (row === undefined) return 'unchanged';
      return row.created ? 'created' : 'changed';
    },

    async remove(checkIn, member) {
      await db
        .deleteFrom('check_in_reactions')
        .where('check_in_id', '=', checkIn)
        .where('member_id', '=', member)
        .execute();
    },

    async list(checkIn) {
      const rows = await db
        .selectFrom('check_in_reactions')
        .select(['member_id', 'kind', 'reacted_at'])
        .where('check_in_id', '=', checkIn)
        .orderBy('reacted_at')
        .orderBy('member_id')
        .execute();
      return rows.map(fromRow);
    },

    async receivedBy({ member, since, until }) {
      const rows = await db
        .selectFrom('check_in_reactions')
        .innerJoin('check_ins', 'check_ins.id', 'check_in_reactions.check_in_id')
        .select([
          'check_in_reactions.member_id',
          'check_in_reactions.kind',
          'check_in_reactions.reacted_at',
          (eb) =>
            eb
              .selectFrom('check_in_squads')
              .select(
                sql<string[]>`array_agg(check_in_squads.squad_id order by position)`.as('ids'),
              )
              .whereRef('check_in_squads.check_in_id', '=', 'check_ins.id')
              .as('audience'),
        ])
        .where('check_ins.member_id', '=', member)
        .where('check_in_reactions.reacted_at', '>=', since)
        .where('check_in_reactions.reacted_at', '<', until)
        .orderBy('check_in_reactions.reacted_at')
        .orderBy('check_in_reactions.member_id')
        .execute();
      // A kind this release no longer has is left out, not an error.
      return rows.flatMap((row) =>
        ReactionKind.safeParse(row.kind).success
          ? [{ ...fromRow(row), audience: (row.audience ?? []).map((id) => SquadId.parse(id)) }]
          : [],
      );
    },

    async listForAll(checkIns) {
      const byCheckIn = new Map<CheckInId, Reaction[]>();
      if (checkIns.length === 0) return byCheckIn;
      const rows = await db
        .selectFrom('check_in_reactions')
        .select(['check_in_id', 'member_id', 'kind', 'reacted_at'])
        .where('check_in_id', 'in', checkIns)
        .orderBy('reacted_at')
        .orderBy('member_id')
        .execute();
      for (const row of rows) {
        const checkIn = CheckInId.parse(row.check_in_id);
        const reactions = byCheckIn.get(checkIn) ?? [];
        reactions.push({
          member: MemberId.parse(row.member_id),
          kind: ReactionKind.parse(row.kind),
          reactedAt: row.reacted_at,
        });
        byCheckIn.set(checkIn, reactions);
      }
      return byCheckIn;
    },
  };
}
