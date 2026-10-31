import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import {
  createPostgresSquadStore,
  createSquads,
  randomInviteCodes,
  type SquadTables,
} from '@wildcard/squads';
import { createPostgresSportStore, createSports, type SportTables } from '@wildcard/sports';
import { z } from 'zod';

import {
  createPostgresCheckInStore,
  type CheckInTables,
} from '../adapters/postgres-check-in-store.js';
import { createPostgresCommentStore } from '../adapters/postgres-comment-store.js';
import { createPostgresReactionStore } from '../adapters/postgres-reaction-store.js';
import { createPostgresWeeklyPlanStore } from '../adapters/postgres-weekly-plan-store.js';
import { CheckInDraft, CheckInId, MemberId, SquadId } from '../domain/check-in.js';
import { CommentId } from '../domain/comment.js';
import { decodeCursor, encodeCursor } from '../domain/post-cursor.js';
import { Emoji } from '../domain/reaction.js';
import { CommentText } from '../domain/text.js';
import { createCheckIns } from './check-ins.js';

const heart = Emoji.parse('❤️');
const muscle = Emoji.parse('💪');

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<CheckInTables & SquadTables & SportTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());
const membership = createSquads({
  store: createPostgresSquadStore(db),
  inviteCodes: randomInviteCodes,
  aiConsent: () => Promise.resolve(true),
});

let now = new Date('2026-10-18T20:00:00.000Z');
const checkIns = createCheckIns({
  sports: createSports({ store: createPostgresSportStore(db) }),
  store: createPostgresCheckInStore(db),
  membership,
  reactions: createPostgresReactionStore(db),
  comments: createPostgresCommentStore(db),
  plans: createPostgresWeeklyPlanStore(db),
  photos: { exists: () => Promise.resolve(true) },
  calendarOf: () => Promise.resolve(undefined),
  clock: () => now,
});

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

async function newSquad(...members: MemberId[]) {
  const id = SquadId.parse(randomUUID());
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${id})`.execute(
    db,
  );
  for (const member of members) {
    await sql`insert into public.squad_members (squad_id, member_id) values (${id}, ${member})`.execute(
      db,
    );
  }
  return id;
}

async function leave(squad: SquadId, member: MemberId) {
  await sql`delete from public.squad_members where squad_id = ${squad} and member_id = ${member}`.execute(
    db,
  );
}

type PostFields = { readonly at: string; readonly audience: readonly SquadId[] } & Record<
  string,
  unknown
>;

/** A check-in by `member` made `at` (on that UTC day); a 练了 run unless `fields` say. */
async function post(member: MemberId, { at, ...fields }: PostFields) {
  now = new Date(Date.parse(at) + 60_000);
  const id = CheckInId.parse(randomUUID());
  await checkIns.save({
    id,
    member,
    draft: CheckInDraft.parse({
      version: 1,
      day: at.slice(0, 10),
      createdAt: at,
      ...('kind' in fields ? {} : { kind: 'trained', training: { sport: 'run' } }),
      ...fields,
    }),
  });
  return id;
}

const ids = (page: {
  readonly posts: readonly { readonly checkIn: { readonly id: CheckInId } }[];
}) => page.posts.map(({ checkIn }) => checkIn.id);

describe('a member’s history (历史动态)', () => {
  it('pages through all their own check-ins, newest first, with the counts on the first page', async () => {
    const [me, friend] = [await newMember(), await newMember()];
    const [squad, other] = [await newSquad(me, friend), await newSquad(me)];
    const oldest = await post(me, { at: '2026-10-10T08:00:00.000Z', audience: [squad] });
    const morning = await post(me, {
      at: '2026-10-12T08:00:00.000Z',
      audience: [other],
      kind: 'healthyMeal',
      meal: {},
    });
    const evening = await post(me, { at: '2026-10-12T20:00:00.000Z', audience: [squad, other] });
    const newest = await post(me, {
      at: '2026-10-14T08:00:00.000Z',
      audience: [squad],
      kind: 'disclaimer',
      disclaimer: { text: '腿请假' },
    });
    await post(friend, { at: '2026-10-14T09:00:00.000Z', audience: [squad] });
    await checkIns.react({ checkIn: evening, member: friend, emoji: heart });

    const first = await checkIns.listMyPosts({ member: me, limit: 2 });
    expect(ids(first)).toStrictEqual([newest, evening]);
    expect(first.counts).toStrictEqual({ posts: 4, reactions: 1 });
    expect(first.posts[1]?.checkIn.audience).toStrictEqual([squad, other]);
    expect(first.posts[1]?.reactions.map(({ member, emoji }) => ({ member, emoji }))).toStrictEqual(
      [{ member: friend, emoji: heart }],
    );
    expect(first.next).toStrictEqual({
      day: '2026-10-12',
      createdAt: new Date('2026-10-12T20:00:00.000Z'),
      id: evening,
    });

    // A post made meanwhile never shifts the next page.
    await post(me, { at: '2026-10-14T21:00:00.000Z', audience: [squad] });
    const second = await checkIns.listMyPosts({ member: me, after: first.next, limit: 2 });
    expect(ids(second)).toStrictEqual([morning, oldest]);
    expect(second.counts).toBeUndefined();
    // The page that reaches the first check-in says no more follow.
    expect(second.next).toBeUndefined();
  });

  it('narrows to one kind, leaving the counts whole', async () => {
    const me = await newMember();
    const squad = await newSquad(me);
    await post(me, { at: '2026-10-15T08:00:00.000Z', audience: [squad] });
    const meal = await post(me, {
      at: '2026-10-15T12:00:00.000Z',
      audience: [squad],
      kind: 'cheatMeal',
      meal: { caption: '火锅' },
    });
    const page = await checkIns.listMyPosts({ member: me, kind: 'cheatMeal', limit: 30 });
    expect(ids(page)).toStrictEqual([meal]);
    expect(page.counts).toStrictEqual({ posts: 2, reactions: 0 });
    expect(page.next).toBeUndefined();
  });

  it('keeps posts to a squad they left, without that squad’s reactions or comments', async () => {
    const [me, friend, stranger] = [await newMember(), await newMember(), await newMember()];
    const [left, stayed] = [await newSquad(me, friend), await newSquad(me, stranger)];
    const toLeft = await post(me, { at: '2026-10-16T08:00:00.000Z', audience: [left] });
    const toBoth = await post(me, { at: '2026-10-16T09:00:00.000Z', audience: [left, stayed] });
    await checkIns.react({ checkIn: toLeft, member: friend, emoji: heart });
    await checkIns.react({ checkIn: toBoth, member: friend, emoji: heart });
    await checkIns.react({ checkIn: toBoth, member: stranger, emoji: muscle });
    const say = (member: MemberId, words: string) =>
      checkIns.comment({
        checkIn: toBoth,
        id: CommentId.parse(randomUUID()),
        member,
        text: CommentText.parse(words),
      });
    await say(friend, '我在左边');
    await say(stranger, '加油');
    await say(me, '谢谢');
    await leave(left, me);

    const page = await checkIns.listMyPosts({ member: me, limit: 30 });
    expect(
      page.posts.map(({ checkIn, reactions }) => ({
        id: checkIn.id,
        from: reactions.map(({ member }) => member),
      })),
    ).toStrictEqual([
      { id: toBoth, from: [stranger] },
      { id: toLeft, from: [] },
    ]);
    // Their own comment, and those of the squad they still share; never the one they left.
    expect(page.posts[0]?.comments.map(({ member, text }) => ({ member, text }))).toStrictEqual([
      { member: stranger, text: '加油' },
      { member: me, text: '谢谢' },
    ]);
    expect(page.posts[1]?.comments).toStrictEqual([]);
    expect(page.counts).toStrictEqual({ posts: 2, reactions: 1 });
  });

  it('shows nobody else’s check-ins', async () => {
    const [me, friend] = [await newMember(), await newMember()];
    const squad = await newSquad(me, friend);
    await post(friend, { at: '2026-10-17T08:00:00.000Z', audience: [squad] });
    expect(await checkIns.listMyPosts({ member: me, limit: 30 })).toStrictEqual({
      posts: [],
      counts: { posts: 0, reactions: 0 },
    });
  });
});

describe('the history’s cursor', () => {
  it('reads back what it wrote, and nothing else', () => {
    const cursor = {
      day: '2026-10-18',
      createdAt: new Date('2026-10-18T19:30:00.123Z'),
      id: CheckInId.parse('9b2f8c1e-4d3a-4f5b-8a6c-7e1d2c3b4a59'),
    };
    expect(decodeCursor(encodeCursor(cursor))).toStrictEqual(cursor);
    expect(decodeCursor('not-a-cursor')).toBeUndefined();
    expect(decodeCursor(Buffer.from('["2026-10-18"]').toString('base64url'))).toBeUndefined();
    const unversioned = ['2026-10-18', '2026-10-18T19:30:00.123Z', cursor.id];
    expect(
      decodeCursor(Buffer.from(JSON.stringify(unversioned)).toString('base64url')),
    ).toBeUndefined();
    const later = {
      version: 2,
      day: '2026-10-18',
      createdAt: '2026-10-18T19:30:00.123Z',
      id: cursor.id,
    };
    expect(decodeCursor(Buffer.from(JSON.stringify(later)).toString('base64url'))).toBeUndefined();
  });
});
