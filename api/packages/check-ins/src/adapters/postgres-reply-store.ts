import { sql, type Kysely } from 'kysely';

import { CheckInId, MemberId } from '../domain/check-in.js';
import { ReplyKind, type Reply } from '../domain/reply.js';
import type { ReplyStore } from '../ports.js';
import type { DB } from './tables.js';

const fromRow = (row: { member_id: string; kind: string; replied_at: Date }): Reply => ({
  member: MemberId.parse(row.member_id),
  kind: ReplyKind.parse(row.kind),
  repliedAt: row.replied_at,
});

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
      return rows.map(fromRow);
    },

    async listForAll(checkIns) {
      const byCheckIn = new Map<CheckInId, Reply[]>();
      if (checkIns.length === 0) return byCheckIn;
      const rows = await db
        .selectFrom('disclaimer_replies')
        .select(['check_in_id', 'member_id', 'kind', 'replied_at'])
        .where('check_in_id', 'in', checkIns)
        .orderBy('replied_at')
        .orderBy('member_id')
        .execute();
      for (const row of rows) {
        const checkIn = CheckInId.parse(row.check_in_id);
        const replies = byCheckIn.get(checkIn) ?? [];
        replies.push(fromRow(row));
        byCheckIn.set(checkIn, replies);
      }
      return byCheckIn;
    },
  };
}
