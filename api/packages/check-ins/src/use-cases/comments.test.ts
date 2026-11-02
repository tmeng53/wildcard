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
import { CommentText } from '../domain/text.js';
import {
  CheckInNotFoundError,
  CommentIdConflictError,
  NotYourCommentError,
  ReplyToNotInSquadError,
} from '../errors.js';
import { createCheckIns } from './check-ins.js';

const text = (words: string) => CommentText.parse(words);
const newId = () => CommentId.parse(randomUUID());

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<CheckInTables & SquadTables & SportTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());
// Who is in which squad, from the squads module as main.ts wires it.
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
  for (const member of members) await join(id, member);
  return id;
}

async function join(squad: SquadId, member: MemberId) {
  await sql`insert into public.squad_members (squad_id, member_id) values (${squad}, ${member})`.execute(
    db,
  );
}

/** A 练了 run on the 18th by `member`, sent to `audience`. */
async function trained(member: MemberId, ...audience: SquadId[]) {
  now = new Date('2026-10-18T20:00:00.000Z');
  const id = CheckInId.parse(randomUUID());
  const { checkIn } = await checkIns.save({
    id,
    member,
    draft: CheckInDraft.parse({
      version: 1,
      day: '2026-10-18',
      createdAt: '2026-10-18T19:30:00.000Z',
      kind: 'trained',
      training: { sport: 'run' },
      audience,
    }),
  });
  return checkIn;
}

describe('commenting on a check-in', () => {
  it('writes comments from teammates and the author, which everyone who sees it reads in order', async () => {
    const [tracy, ann, bo] = [await newMember(), await newMember(), await newMember()];
    const squad = await newSquad(tracy, ann, bo);
    const run = await trained(tracy, squad);
    const [first, second] = [newId(), newId()];

    now = new Date('2026-10-18T20:05:00.000Z');
    const written = await checkIns.comment({
      checkIn: run.id,
      id: first,
      member: ann,
      text: text('  明天我也练腿  '),
    });
    expect(written).toStrictEqual({
      comment: {
        id: first,
        member: ann,
        text: '明天我也练腿',
        commentedAt: new Date('2026-10-18T20:05:00.000Z'),
      },
      created: true,
    });
    now = new Date('2026-10-18T20:06:00.000Z');
    await checkIns.comment({
      checkIn: run.id,
      id: second,
      member: tracy,
      text: text('电梯见'),
      replyTo: ann,
    });

    const expected = [
      {
        id: first,
        member: ann,
        text: '明天我也练腿',
        commentedAt: new Date('2026-10-18T20:05:00.000Z'),
      },
      {
        id: second,
        member: tracy,
        text: '电梯见',
        replyTo: ann,
        commentedAt: new Date('2026-10-18T20:06:00.000Z'),
      },
    ];
    expect(await checkIns.listComments({ checkIn: run.id, viewer: bo })).toStrictEqual(expected);
    const [post] = await checkIns.listForSquad({
      viewer: tracy,
      squad,
      days: { from: '2026-10-18', to: '2026-10-18' },
    });
    expect(post?.comments).toStrictEqual(expected);
  });

  it('saves a retry once, and refuses an id that holds another comment', async () => {
    const [tracy, ann] = [await newMember(), await newMember()];
    const run = await trained(tracy, await newSquad(tracy, ann));
    const id = newId();

    now = new Date('2026-10-18T20:05:00.000Z');
    await checkIns.comment({ checkIn: run.id, id, member: ann, text: text('加油') });
    now = new Date('2026-10-18T20:07:00.000Z');
    const again = await checkIns.comment({ checkIn: run.id, id, member: ann, text: text('加油') });
    expect([again.created, again.comment.commentedAt]).toStrictEqual([
      false,
      new Date('2026-10-18T20:05:00.000Z'),
    ]);
    await expect(
      checkIns.comment({ checkIn: run.id, id, member: ann, text: text('不加了') }),
    ).rejects.toStrictEqual(new CommentIdConflictError(id));
    await expect(
      checkIns.comment({ checkIn: run.id, id, member: tracy, text: text('加油') }),
    ).rejects.toStrictEqual(new CommentIdConflictError(id));
    expect(await checkIns.listComments({ checkIn: run.id, viewer: tracy })).toHaveLength(1);
  });

  it('refuses a reply to someone who can’t see the check-in', async () => {
    const [tracy, ann, stranger] = [await newMember(), await newMember(), await newMember()];
    const run = await trained(tracy, await newSquad(tracy, ann));
    await newSquad(ann, stranger);

    await expect(
      checkIns.comment({
        checkIn: run.id,
        id: newId(),
        member: ann,
        text: text('你看'),
        replyTo: stranger,
      }),
    ).rejects.toStrictEqual(new ReplyToNotInSquadError());
  });

  it('deletes only your own comment, and deleting it again is fine', async () => {
    const [tracy, ann] = [await newMember(), await newMember()];
    const run = await trained(tracy, await newSquad(tracy, ann));
    const id = newId();
    await checkIns.comment({ checkIn: run.id, id, member: ann, text: text('加油') });

    // Not even the post's author deletes someone else's.
    await expect(
      checkIns.deleteComment({ checkIn: run.id, id, member: tracy }),
    ).rejects.toStrictEqual(new NotYourCommentError());
    await checkIns.deleteComment({ checkIn: run.id, id, member: ann });
    await checkIns.deleteComment({ checkIn: run.id, id, member: ann });
    expect(await checkIns.listComments({ checkIn: run.id, viewer: tracy })).toStrictEqual([]);
  });

  it('answers not found for a check-in you share no squad on', async () => {
    const [tracy, ann, stranger] = [await newMember(), await newMember(), await newMember()];
    await newSquad(tracy, stranger);
    const run = await trained(tracy, await newSquad(tracy, ann));
    const anns = newId();
    await checkIns.comment({ checkIn: run.id, id: anns, member: ann, text: text('好') });

    for (const attempt of [
      () => checkIns.comment({ checkIn: run.id, id: newId(), member: stranger, text: text('嗨') }),
      () => checkIns.deleteComment({ checkIn: run.id, id: anns, member: stranger }),
      () => checkIns.listComments({ checkIn: run.id, viewer: stranger }),
    ]) {
      await expect(attempt()).rejects.toStrictEqual(new CheckInNotFoundError(run.id));
    }
  });

  it('hides comments from members of a squad the viewer isn’t in', async () => {
    const [tracy, ann, bo] = [await newMember(), await newMember(), await newMember()];
    const ours = await newSquad(tracy, ann);
    const theirs = await newSquad(tracy, bo);
    const run = await trained(tracy, ours, theirs);
    await checkIns.comment({ checkIn: run.id, id: newId(), member: bo, text: text('冲') });
    await checkIns.comment({ checkIn: run.id, id: newId(), member: ann, text: text('好') });

    const seen = await checkIns.listComments({ checkIn: run.id, viewer: ann });
    expect(seen.map(({ member }) => member)).toStrictEqual([ann]);
  });

  it('counts teammates who commented on the member’s posts, never the member', async () => {
    const [tracy, ann, bo] = [await newMember(), await newMember(), await newMember()];
    const run = await trained(tracy, await newSquad(tracy, ann, bo));
    now = new Date('2026-10-18T20:05:00.000Z');
    await checkIns.comment({ checkIn: run.id, id: newId(), member: ann, text: text('一') });
    await checkIns.comment({ checkIn: run.id, id: newId(), member: ann, text: text('二') });
    await checkIns.comment({ checkIn: run.id, id: newId(), member: tracy, text: text('三') });
    now = new Date('2026-10-18T21:00:00.000Z');
    await checkIns.comment({ checkIn: run.id, id: newId(), member: bo, text: text('晚了') });

    expect(
      await checkIns.commentsReceived({
        member: tracy,
        since: new Date('2026-10-18T20:00:00.000Z'),
        until: new Date('2026-10-18T21:00:00.000Z'),
      }),
    ).toStrictEqual(new Set([ann]));
  });

  it('never changes a comment in the database', async () => {
    const [tracy, ann] = [await newMember(), await newMember()];
    const run = await trained(tracy, await newSquad(tracy, ann));
    const id = newId();
    await checkIns.comment({ checkIn: run.id, id, member: ann, text: text('原话') });

    await expect(
      sql`update public.check_in_comments set text = 'changed' where id = ${id}`.execute(db),
    ).rejects.toThrow('check_in_comments can');
  });
});
