import { sql, type Kysely } from 'kysely';

import { MemberId } from '../domain/check-in.js';
import { ReactionKind } from '../domain/reaction.js';
import type { ReactionStore } from '../ports.js';
import type { DB } from './tables.js';

/** The reaction store on Postgres (`supabase/migrations`). */
export function createPostgresReactionStore(db: Kysely<DB>): ReactionStore {
  return {
    async save(checkIn, { member, kind, reactedAt }) {
      // One statement, so two reactions at once can't both count as new. The update runs only
      // for a different kind or a reaction put back; `xmax = 0` tells a fresh row from an
      // updated one.
      const row = await db
        .insertInto('check_in_reactions')
        .values({ check_in_id: checkIn, member_id: member, kind, reacted_at: reactedAt })
        .onConflict((conflict) =>
          conflict
            .columns(['check_in_id', 'member_id'])
            .doUpdateSet({ kind, reacted_at: reactedAt, removed_at: null })
            .where((where) =>
              where.or([
                where('check_in_reactions.kind', '<>', kind),
                where('check_in_reactions.removed_at', 'is not', null),
              ]),
            ),
        )
        .returning(sql<boolean>`xmax = 0`.as('created'))
        .executeTakeFirst();
      if (row === undefined) return 'unchanged';
      return row.created ? 'created' : 'changed';
    },

    async remove(checkIn, member) {
      // Kept with the time it was taken off: putting it back isn't a new reaction.
      await db
        .updateTable('check_in_reactions')
        .set({ removed_at: sql`now()` })
        .where('check_in_id', '=', checkIn)
        .where('member_id', '=', member)
        .where('removed_at', 'is', null)
        .execute();
    },

    async list(checkIn) {
      const rows = await db
        .selectFrom('check_in_reactions')
        .select(['member_id', 'kind', 'reacted_at'])
        .where('check_in_id', '=', checkIn)
        .where('removed_at', 'is', null)
        .orderBy('reacted_at')
        .orderBy('member_id')
        .execute();
      return rows.map((row) => ({
        member: MemberId.parse(row.member_id),
        kind: ReactionKind.parse(row.kind),
        reactedAt: row.reacted_at,
      }));
    },
  };
}
