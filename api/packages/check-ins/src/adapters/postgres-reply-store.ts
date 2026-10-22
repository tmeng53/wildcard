import { sql, type Kysely } from 'kysely';

import { MemberId } from '../domain/check-in.js';
import { ReplyKind } from '../domain/reply.js';
import type { ReplyStore } from '../ports.js';
import type { DB } from './tables.js';

/** The 请假条 reply store on Postgres (`supabase/migrations`). */
export function createPostgresReplyStore(db: Kysely<DB>): ReplyStore {
  return {
    async save(checkIn, { member, kind, repliedAt }) {
      // As with reactions: one statement, the update only for a different kind, and `xmax = 0`
      // tells a fresh row from an updated one.
      const row = await db
        .insertInto('disclaimer_replies')
        .values({ check_in_id: checkIn, member_id: member, kind, replied_at: repliedAt })
        .onConflict((conflict) =>
          conflict
            .columns(['check_in_id', 'member_id'])
            .doUpdateSet({ kind, replied_at: repliedAt })
            .where('disclaimer_replies.kind', '<>', kind),
        )
        .returning(sql<boolean>`xmax = 0`.as('created'))
        .executeTakeFirst();
      if (row === undefined) return 'unchanged';
      return row.created ? 'created' : 'changed';
    },

    async remove(checkIn, member) {
      await db
        .deleteFrom('disclaimer_replies')
        .where('check_in_id', '=', checkIn)
        .where('member_id', '=', member)
        .execute();
    },

    async list(checkIn) {
      const rows = await db
        .selectFrom('disclaimer_replies')
        .select(['member_id', 'kind', 'replied_at'])
        .where('check_in_id', '=', checkIn)
        .orderBy('replied_at')
        .orderBy('member_id')
        .execute();
      return rows.map((row) => ({
        member: MemberId.parse(row.member_id),
        kind: ReplyKind.parse(row.kind),
        repliedAt: row.replied_at,
      }));
    },
  };
}
