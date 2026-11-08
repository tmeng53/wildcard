import type { Kysely } from 'kysely';

import {
  FeedbackId,
  FeedbackKind,
  MemberId,
  StoredAppInfo,
  type Feedback,
} from '../domain/feedback.js';
import type { FeedbackStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type FeedbackTables = DB;

/** The feedback store on Postgres (`supabase/migrations`). */
export function createPostgresFeedbackStore(db: Kysely<FeedbackTables>): FeedbackStore {
  return {
    async add({ id, member, kind, body, screenshots, app, at }) {
      const inserted = await db
        .insertInto('feedback')
        .values({
          id,
          member_id: member,
          kind,
          body,
          screenshots: [...screenshots],
          app: JSON.stringify({ version: 1, ...app }),
          at,
        })
        .onConflict((conflict) => conflict.column('id').doNothing())
        .returning('id')
        .executeTakeFirst();
      if (inserted !== undefined) return { outcome: 'created' };
      const row = await db
        .selectFrom('feedback')
        .select('member_id')
        .where('id', '=', id)
        .executeTakeFirstOrThrow();
      return { outcome: 'unchanged', member: MemberId.parse(row.member_id) };
    },

    async senderOf(id) {
      const row = await db
        .selectFrom('feedback')
        .select('member_id')
        .where('id', '=', id)
        .executeTakeFirst();
      return row === undefined ? undefined : MemberId.parse(row.member_id);
    },

    async countSince(member, since) {
      const row = await db
        .selectFrom('feedback')
        .select((eb) => eb.fn.countAll<string>().as('count'))
        .where('member_id', '=', member)
        .where('at', '>', since)
        .executeTakeFirstOrThrow();
      return Number(row.count);
    },

    async unfiled(before, limit) {
      const rows = await db
        .selectFrom('feedback')
        .leftJoin('feedback_issues', 'feedback_issues.feedback_id', 'feedback.id')
        .select([
          'feedback.id',
          'feedback.member_id',
          'feedback.kind',
          'feedback.body',
          'feedback.screenshots',
          'feedback.app',
          'feedback.at',
        ])
        .where('feedback_issues.feedback_id', 'is', null)
        .where('feedback.at', '<', before)
        .orderBy('feedback.at')
        .limit(limit)
        .execute();
      return rows.map((row): Feedback => ({
        id: FeedbackId.parse(row.id),
        member: MemberId.parse(row.member_id),
        kind: FeedbackKind.parse(row.kind),
        body: row.body,
        screenshots: row.screenshots,
        app: StoredAppInfo.parse(row.app),
        at: new Date(row.at),
      }));
    },

    async filed({ id, issue: { number, url }, at }) {
      await db
        .insertInto('feedback_issues')
        .values({ feedback_id: id, number, url, at })
        .onConflict((conflict) => conflict.column('feedback_id').doNothing())
        .execute();
    },
  };
}
