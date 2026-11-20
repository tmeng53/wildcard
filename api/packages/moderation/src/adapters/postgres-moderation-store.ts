import { sql, type Kysely } from 'kysely';
import { z } from 'zod';

import {
  MemberId,
  ReportId,
  ReportKind,
  coachReplyKey,
  type Hidden,
  type Report,
} from '../domain/moderation.js';
import type { ModerationStore } from '../ports.js';

import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type ModerationTables = DB;

/** What a report copied, as its row keeps it. */
const StoredSnapshot = z.strictObject({
  version: z.literal(1),
  words: z.string().optional(),
  photos: z.number().int().nonnegative().optional(),
});

interface ReportRow {
  readonly id: string;
  readonly member_id: string;
  readonly kind: string;
  readonly check_in_id: string;
  readonly item_id: string | null;
  readonly author_id: string | null;
  readonly snapshot: unknown;
  readonly at: Date | string;
}

function reportOf(row: ReportRow): Report {
  const { words, photos } = StoredSnapshot.parse(row.snapshot);
  return {
    id: ReportId.parse(row.id),
    member: MemberId.parse(row.member_id),
    kind: ReportKind.parse(row.kind),
    checkIn: row.check_in_id,
    ...(row.item_id === null ? {} : { item: row.item_id }),
    ...(row.author_id === null ? {} : { author: MemberId.parse(row.author_id) }),
    snapshot: {
      ...(words === undefined ? {} : { words }),
      ...(photos === undefined ? {} : { photos }),
    },
    at: new Date(row.at),
  };
}

/**
 * The moderation store on Postgres (`supabase/migrations`): `member_blocks` is the blocks' log,
 * `content_reports` the reports and `content_report_issues` where each was filed.
 */
export function createPostgresModerationStore(db: Kysely<ModerationTables>): ModerationStore {
  /** Each pair's latest row, either way round, where it stands blocked. */
  const blocksTouching = (member: MemberId) => sql<{
    member_id: string;
    other_id: string;
    at: Date;
  }>`
    select member_id, other_id, at from (
      select distinct on (member_id, other_id) member_id, other_id, kind, at
      from public.member_blocks
      where member_id = ${member} or other_id = ${member}
      order by member_id, other_id, id desc
    ) as latest
    where kind = 'blocked'
  `;

  return {
    async blockedBy(member) {
      const { rows } = await blocksTouching(member).execute(db);
      return rows
        .filter((row) => row.member_id === member)
        .map((row) => ({ member: MemberId.parse(row.other_id), since: new Date(row.at) }))
        .sort((a, b) => b.since.getTime() - a.since.getTime());
    },

    async log({ member, other, kind, at }) {
      await db
        .insertInto('member_blocks')
        .values({ member_id: member, other_id: other, kind, at })
        .execute();
    },

    async hiddenFor(member): Promise<Hidden> {
      const [{ rows }, reports] = await Promise.all([
        blocksTouching(member).execute(db),
        db
          .selectFrom('content_reports')
          .select(['kind', 'check_in_id', 'item_id'])
          .where('member_id', '=', member)
          .execute(),
      ]);
      const members = new Set(
        rows.map((row) => (row.member_id === member ? row.other_id : row.member_id)),
      );
      const ofKind = (kind: string) =>
        new Set(
          reports
            .filter((row) => row.kind === kind)
            .map((row) =>
              kind === 'checkIn'
                ? row.check_in_id
                : kind === 'coachReply'
                  ? coachReplyKey(row.check_in_id, row.item_id ?? '')
                  : (row.item_id ?? ''),
            ),
        );
      return {
        members,
        checkIns: ofKind('checkIn'),
        comments: ofKind('comment'),
        coachReplies: ofKind('coachReply'),
        coachAnswers: ofKind('coachAnswer'),
      };
    },

    async blockedAmong(member, members) {
      const { rows } = await blocksTouching(member).execute(db);
      const wanted = new Set<string>(members);
      const found = new Set<string>();
      for (const row of rows) {
        const other = row.member_id === member ? row.other_id : row.member_id;
        if (wanted.has(other)) found.add(other);
      }
      return found;
    },

    async report(report) {
      const { id, member, kind, checkIn, item, author, snapshot, at } = report;
      const inserted = await db
        .insertInto('content_reports')
        .values({
          id,
          member_id: member,
          kind,
          check_in_id: checkIn,
          item_id: item ?? null,
          author_id: author ?? null,
          snapshot: JSON.stringify({ version: 1, ...snapshot }),
          at,
        })
        .onConflict((conflict) => conflict.doNothing())
        .returning('id')
        .executeTakeFirst();
      if (inserted !== undefined) return { report, fresh: true };
      const standing =
        (await db
          .selectFrom('content_reports')
          .selectAll()
          .where('id', '=', id)
          .executeTakeFirst()) ??
        (await db
          .selectFrom('content_reports')
          .selectAll()
          .where('member_id', '=', member)
          .where('kind', '=', kind)
          .where('check_in_id', '=', checkIn)
          .where(sql<string>`coalesce(item_id, '')`, '=', item ?? '')
          .executeTakeFirstOrThrow());
      return { report: reportOf(standing), fresh: false };
    },

    async unfiled(before, limit) {
      const rows = await db
        .selectFrom('content_reports')
        .leftJoin('content_report_issues', 'content_report_issues.report_id', 'content_reports.id')
        .selectAll('content_reports')
        .where('content_report_issues.report_id', 'is', null)
        .where('content_reports.at', '<', before)
        .orderBy('content_reports.at')
        .limit(limit)
        .execute();
      return rows.map(reportOf);
    },

    async filed({ id, issue, at }) {
      await db
        .insertInto('content_report_issues')
        .values({ report_id: id, number: issue.number, url: issue.url, at })
        .onConflict((conflict) => conflict.column('report_id').doNothing())
        .execute();
    },
  };
}
