import { sql, type Kysely } from 'kysely';

import {
  AdoptionKind,
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
    add({ id, member, kind, body, screenshots, app, at }, { limit, since }) {
      return db.transaction().execute(async (trx) => {
        // One member's messages are counted and saved one at a time, so a burst can't all pass
        // the limit together.
        await sql`select pg_advisory_xact_lock(hashtext('feedback'), hashtext(${member}))`.execute(
          trx,
        );
        const existing = await trx
          .selectFrom('feedback')
          .select('member_id')
          .where('id', '=', id)
          .executeTakeFirst();
        if (existing !== undefined) {
          return { outcome: 'unchanged', member: MemberId.parse(existing.member_id) } as const;
        }
        const sent = await trx
          .selectFrom('feedback')
          .select((eb) => eb.fn.countAll<string>().as('count'))
          .where('member_id', '=', member)
          .where('at', '>', since)
          .executeTakeFirstOrThrow();
        if (Number(sent.count) >= limit) return { outcome: 'limited' } as const;
        const inserted = await trx
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
        if (inserted !== undefined) return { outcome: 'created' } as const;
        // Another member's message took the id between the look and the save.
        const row = await trx
          .selectFrom('feedback')
          .select('member_id')
          .where('id', '=', id)
          .executeTakeFirstOrThrow();
        return { outcome: 'unchanged', member: MemberId.parse(row.member_id) } as const;
      });
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

    async adopt({ feedback, kind, admin, at }) {
      const sent = await db
        .selectFrom('feedback')
        .select('member_id')
        .where('id', '=', feedback)
        .executeTakeFirst();
      if (sent === undefined) return undefined;
      const inserted = await db
        .insertInto('feedback_adoptions')
        .values({ feedback_id: feedback, kind, admin_id: admin, at })
        .onConflict((conflict) => conflict.column('feedback_id').doNothing())
        .returning('feedback_id')
        .executeTakeFirst();
      const kept = await db
        .selectFrom('feedback_adoptions')
        .selectAll()
        .where('feedback_id', '=', feedback)
        .executeTakeFirstOrThrow();
      return {
        adoption: {
          feedback,
          member: MemberId.parse(sent.member_id),
          kind: AdoptionKind.parse(kept.kind),
          admin: MemberId.parse(kept.admin_id),
          at: new Date(kept.at),
        },
        fresh: inserted !== undefined,
      };
    },
  };
}
