import { sql, type Kysely } from 'kysely';

import { CheckInId, MemberId, SquadId } from '../domain/check-in.js';
import { CommentId, sameComment, type Comment } from '../domain/comment.js';
import { CommentText } from '../domain/text.js';
import type { CommentStore } from '../ports.js';
import type { DB } from './tables.js';

interface Row {
  readonly id: string;
  readonly member_id: string;
  readonly text: string;
  readonly reply_to: string | null;
  readonly commented_at: Date;
}

const fromRow = (row: Row): Comment => ({
  id: CommentId.parse(row.id),
  member: MemberId.parse(row.member_id),
  text: CommentText.parse(row.text),
  ...(row.reply_to === null ? {} : { replyTo: MemberId.parse(row.reply_to) }),
  commentedAt: row.commented_at,
});

const COLUMNS = ['id', 'member_id', 'text', 'reply_to', 'commented_at'] as const;

/** The comment store on Postgres (`supabase/migrations`). */
export function createPostgresCommentStore(db: Kysely<DB>): CommentStore {
  const store: CommentStore = {
    async insert(checkIn, { id, member, text, replyTo, commentedAt }) {
      // One statement, so two saves of one id at once can't both count as new.
      const row = await db
        .insertInto('check_in_comments')
        .values({
          id,
          check_in_id: checkIn,
          member_id: member,
          text,
          reply_to: replyTo ?? null,
          commented_at: commentedAt,
        })
        .onConflict((conflict) => conflict.column('id').doNothing())
        .returning('id')
        .executeTakeFirst();
      if (row !== undefined) return 'created';
      const saved = await store.find(id);
      return saved?.checkIn === checkIn && sameComment(saved, { member, text, replyTo })
        ? 'unchanged'
        : 'conflict';
    },

    async find(id) {
      const row = await db
        .selectFrom('check_in_comments')
        .select([...COLUMNS, 'check_in_id'])
        .where('id', '=', id)
        .executeTakeFirst();
      return row === undefined
        ? undefined
        : { ...fromRow(row), checkIn: CheckInId.parse(row.check_in_id) };
    },

    async remove(id) {
      await db.deleteFrom('check_in_comments').where('id', '=', id).execute();
    },

    async list(checkIn) {
      const rows = await db
        .selectFrom('check_in_comments')
        .select(COLUMNS)
        .where('check_in_id', '=', checkIn)
        .orderBy('commented_at')
        .orderBy('id')
        .execute();
      return rows.map(fromRow);
    },

    async listForAll(checkIns) {
      const byCheckIn = new Map<CheckInId, Comment[]>();
      if (checkIns.length === 0) return byCheckIn;
      const rows = await db
        .selectFrom('check_in_comments')
        .select([...COLUMNS, 'check_in_id'])
        .where('check_in_id', 'in', checkIns)
        .orderBy('commented_at')
        .orderBy('id')
        .execute();
      for (const row of rows) {
        const checkIn = CheckInId.parse(row.check_in_id);
        const comments = byCheckIn.get(checkIn) ?? [];
        comments.push(fromRow(row));
        byCheckIn.set(checkIn, comments);
      }
      return byCheckIn;
    },

    async receivedBy({ member, since, until }) {
      const rows = await db
        .selectFrom('check_in_comments')
        .innerJoin('check_ins', 'check_ins.id', 'check_in_comments.check_in_id')
        .select([
          'check_in_comments.id',
          'check_in_comments.member_id',
          'check_in_comments.text',
          'check_in_comments.reply_to',
          'check_in_comments.commented_at',
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
        .where('check_in_comments.member_id', '<>', member)
        .where('check_in_comments.commented_at', '>=', since)
        .where('check_in_comments.commented_at', '<', until)
        .orderBy('check_in_comments.commented_at')
        .orderBy('check_in_comments.id')
        .execute();
      return rows.map((row) => ({
        ...fromRow(row),
        audience: (row.audience ?? []).map((id) => SquadId.parse(id)),
      }));
    },
  };
  return store;
}
