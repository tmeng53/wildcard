import { sql, type Kysely } from 'kysely';

import { NoticeId, parseNotice, type Notice } from '../domain/notice.js';
import type { NoticeStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type NoticeTables = DB;

/** The notice store on Postgres (`supabase/migrations`). */
export function createPostgresNoticeStore(db: Kysely<NoticeTables>): NoticeStore {
  return {
    async add(notices) {
      if (notices.length === 0) return;
      await db
        .insertInto('notices')
        .values(
          notices.map(({ member, squad, kind, subject }) => ({
            member_id: member,
            squad_id: squad ?? null,
            kind,
            subject: JSON.stringify(subject),
          })),
        )
        .execute();
    },

    async page({ member, before, limit }) {
      let query = db
        .selectFrom('notices')
        .select(['id', 'member_id', 'squad_id', 'kind', 'subject', 'at'])
        .where('member_id', '=', member)
        .orderBy('id', 'desc')
        .limit(limit);
      if (before !== undefined) query = query.where('id', '<', String(before));
      const rows = await query.execute();
      // A kind this build no longer knows is left out, never an error.
      return rows.flatMap((row) => {
        const notice = parseNotice({
          id: Number(row.id),
          member: row.member_id,
          squad: row.squad_id,
          kind: row.kind,
          subject: row.subject,
          at: new Date(row.at),
        });
        return notice === undefined ? [] : [notice];
      }) satisfies Notice[];
    },

    async seenThrough(member) {
      const row = await db
        .selectFrom('notice_reads')
        .select('seen_through')
        .where('member_id', '=', member)
        .orderBy('id', 'desc')
        .limit(1)
        .executeTakeFirst();
      return row === undefined ? undefined : NoticeId.parse(Number(row.seen_through));
    },

    async markSeen(member, through) {
      const own = await db
        .selectFrom('notices')
        .select('id')
        .where('id', '=', String(through))
        .where('member_id', '=', member)
        .executeTakeFirst();
      if (own === undefined) return 'unknown';
      // One statement, so two opens at once never write a row that moves nothing.
      const inserted = await db
        .insertInto('notice_reads')
        .columns(['member_id', 'seen_through'])
        .expression(
          db
            .selectNoFrom([
              sql<string>`${member}::uuid`.as('member_id'),
              sql<string>`${String(through)}::bigint`.as('seen_through'),
            ])
            .where((eb) =>
              eb.not(
                eb.exists(
                  eb
                    .selectFrom('notice_reads')
                    .select('id')
                    .where('member_id', '=', member)
                    .where('seen_through', '>=', String(through)),
                ),
              ),
            ),
        )
        .returning('id')
        .executeTakeFirst();
      return inserted === undefined ? 'unchanged' : 'moved';
    },
  };
}
