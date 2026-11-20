import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresModerationStore,
  type ModerationTables,
} from '../adapters/postgres-moderation-store.js';
import { MemberId, ReportId } from '../domain/moderation.js';
import { BlockSelfError, ReportIdTakenError } from '../errors.js';
import { createModeration } from './moderation.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<ModerationTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

function moderationAt(start: string) {
  let now = new Date(start);
  return {
    moderation: createModeration({ store: createPostgresModerationStore(db), clock: () => now }),
    advance: (to: string) => {
      now = new Date(to);
    },
  };
}

describe('blocking', () => {
  it('hides each from the other, both ways, until unblocked', async () => {
    const [mia, jay, coco] = [await newMember(), await newMember(), await newMember()];
    const { moderation, advance } = moderationAt('2026-11-20T10:00:00Z');

    await moderation.block({ member: mia, other: jay });
    await moderation.block({ member: mia, other: jay });

    expect(await moderation.blocked(mia)).toEqual([
      { member: jay, since: new Date('2026-11-20T10:00:00Z') },
    ]);
    expect(await moderation.blocked(jay)).toEqual([]);
    expect([...(await moderation.hiddenFor(mia)).members]).toEqual([jay]);
    expect([...(await moderation.hiddenFor(jay)).members]).toEqual([mia]);
    expect([...(await moderation.blockedAmong(jay, [mia, coco]))]).toEqual([mia]);
    expect([...(await moderation.blockedAmong(coco, [mia, jay]))]).toEqual([]);

    advance('2026-11-21T10:00:00Z');
    await moderation.unblock({ member: mia, other: jay });
    await moderation.unblock({ member: mia, other: jay });

    expect(await moderation.blocked(mia)).toEqual([]);
    expect((await moderation.hiddenFor(jay)).members.size).toBe(0);
    const { rows } = await sql<{ kind: string }>`
      select kind from public.member_blocks where member_id = ${mia} order by id
    `.execute(db);
    expect(rows.map((row) => row.kind)).toEqual(['blocked', 'unblocked']);
  });

  it('refuses blocking oneself', async () => {
    const mia = await newMember();
    const { moderation } = moderationAt('2026-11-20T10:00:00Z');
    await expect(moderation.block({ member: mia, other: mia })).rejects.toBeInstanceOf(
      BlockSelfError,
    );
  });

  it('keeps the log append-only, and lets an account deletion take its rows', async () => {
    const [mia, jay] = [await newMember(), await newMember()];
    const { moderation } = moderationAt('2026-11-20T10:00:00Z');
    await moderation.block({ member: mia, other: jay });

    await expect(
      sql`update public.member_blocks set kind = 'unblocked' where member_id = ${mia}`.execute(db),
    ).rejects.toThrow(/append-only/);
    await sql`delete from auth.users where id = ${jay}`.execute(db);
    expect(await moderation.blocked(mia)).toEqual([]);
  });
});

describe('reporting', () => {
  it('keeps one report per thing, hides it from the reporter only, and files it once', async () => {
    const [mia, jay] = [await newMember(), await newMember()];
    const { moderation, advance } = moderationAt('2026-11-20T10:00:00Z');
    const checkIn = randomUUID();
    const first = {
      id: ReportId.parse(randomUUID()),
      member: mia,
      kind: 'checkIn' as const,
      checkIn,
      author: jay,
      snapshot: { words: '下雨也跑了', photos: 2 },
    };

    const made = await moderation.report(first);
    const again = await moderation.report({ ...first, id: ReportId.parse(randomUUID()) });
    await moderation.report({
      id: ReportId.parse(randomUUID()),
      member: mia,
      kind: 'comment',
      checkIn,
      item: 'comment-1',
      author: jay,
      snapshot: { words: '鞋：我没签这个合同' },
    });

    expect(made.fresh).toBe(true);
    expect(again).toEqual({
      report: { ...first, at: new Date('2026-11-20T10:00:00Z') },
      fresh: false,
    });
    const hidden = await moderation.hiddenFor(mia);
    expect([...hidden.checkIns]).toEqual([checkIn]);
    expect([...hidden.comments]).toEqual(['comment-1']);
    expect((await moderation.hiddenFor(jay)).checkIns.size).toBe(0);

    advance('2026-11-20T10:30:00Z');
    const waiting = (await moderation.toFile(10 * 60 * 1000, 10_000)).filter(
      (report) => report.member === mia,
    );
    expect(waiting.map((report) => report.kind).sort()).toEqual(['checkIn', 'comment']);
    await moderation.filed(first.id, { number: 7, url: 'https://github.com/x/y/issues/7' });
    await moderation.filed(first.id, { number: 8, url: 'https://github.com/x/y/issues/8' });
    const still = (await moderation.toFile(10 * 60 * 1000, 10_000)).filter(
      (report) => report.member === mia,
    );
    expect(still.map((report) => report.kind)).toEqual(['comment']);
  });

  it('refuses another member’s report id', async () => {
    const [mia, jay] = [await newMember(), await newMember()];
    const { moderation } = moderationAt('2026-11-20T10:00:00Z');
    const id = ReportId.parse(randomUUID());
    await moderation.report({
      id,
      member: mia,
      kind: 'checkIn',
      checkIn: randomUUID(),
      snapshot: {},
    });
    await expect(
      moderation.report({ id, member: jay, kind: 'checkIn', checkIn: randomUUID(), snapshot: {} }),
    ).rejects.toBeInstanceOf(ReportIdTakenError);
  });

  it('goes with the author’s account, words and all', async () => {
    const [mia, jay] = [await newMember(), await newMember()];
    const { moderation } = moderationAt('2026-11-20T10:00:00Z');
    const checkIn = randomUUID();
    await moderation.report({
      id: ReportId.parse(randomUUID()),
      member: mia,
      kind: 'checkIn',
      checkIn,
      author: jay,
      snapshot: { words: 'hi' },
    });
    await sql`delete from auth.users where id = ${jay}`.execute(db);
    expect((await moderation.hiddenFor(mia)).checkIns.size).toBe(0);
  });
});
