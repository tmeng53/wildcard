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
import { z } from 'zod';

import {
  createPostgresCheckInStore,
  type CheckInTables,
} from '../adapters/postgres-check-in-store.js';
import { createPostgresReactionStore } from '../adapters/postgres-reaction-store.js';
import { createPostgresReplyStore } from '../adapters/postgres-reply-store.js';
import { createPostgresWeeklyPlanStore } from '../adapters/postgres-weekly-plan-store.js';
import { CheckInDraft, CheckInId, MemberId, SquadId } from '../domain/check-in.js';
import { CheckInNotFoundError, NotADisclaimerError, OwnDisclaimerReplyError } from '../errors.js';
import { createCheckIns } from './check-ins.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<CheckInTables & SquadTables>({
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
  store: createPostgresCheckInStore(db),
  membership,
  reactions: createPostgresReactionStore(db),
  replies: createPostgresReplyStore(db),
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

/** A check-in on the 18th by `member`, sent to `audience`: a 请假条, or a 练了 run. */
async function posted(
  kind: 'disclaimer' | 'trained',
  { member, audience }: { readonly member: MemberId; readonly audience: readonly SquadId[] },
) {
  now = new Date('2026-10-18T20:00:00.000Z');
  const { checkIn } = await checkIns.save({
    id: CheckInId.parse(randomUUID()),
    member,
    draft: CheckInDraft.parse({
      version: 1,
      day: '2026-10-18',
      createdAt: '2026-10-18T19:30:00.000Z',
      audience,
      ...(kind === 'disclaimer'
        ? { kind, disclaimer: { text: '下雨了，腿说不想动' } }
        : { kind, training: { sport: 'run' } }),
    }),
  });
  return checkIn;
}

describe('replying to a 请假条', () => {
  it('leaves a teammate’s reply, which the author and teammates can read', async () => {
    const [tracy, ann, bo] = [await newMember(), await newMember(), await newMember()];
    const excuse = await posted('disclaimer', {
      member: tracy,
      audience: [await newSquad(tracy, ann, bo)],
    });

    now = new Date('2026-10-18T20:05:00.000Z');
    const replied = await checkIns.reply({ checkIn: excuse.id, member: ann, kind: 'approved' });
    expect([replied.outcome, replied.reply]).toStrictEqual([
      'created',
      { member: ann, kind: 'approved', repliedAt: new Date('2026-10-18T20:05:00.000Z') },
    ]);
    now = new Date('2026-10-18T20:06:00.000Z');
    await checkIns.reply({ checkIn: excuse.id, member: bo, kind: 'hug' });

    const expected = [
      { member: ann, kind: 'approved', repliedAt: new Date('2026-10-18T20:05:00.000Z') },
      { member: bo, kind: 'hug', repliedAt: new Date('2026-10-18T20:06:00.000Z') },
    ];
    expect(await checkIns.listReplies({ checkIn: excuse.id, viewer: tracy })).toStrictEqual(
      expected,
    );
    expect(await checkIns.listReplies({ checkIn: excuse.id, viewer: bo })).toStrictEqual(expected);
  });

  it('keeps one reply per member: a different one replaces it, the same one changes nothing', async () => {
    const [tracy, ann] = [await newMember(), await newMember()];
    const excuse = await posted('disclaimer', {
      member: tracy,
      audience: [await newSquad(tracy, ann)],
    });

    now = new Date('2026-10-18T20:05:00.000Z');
    await checkIns.reply({ checkIn: excuse.id, member: ann, kind: 'approved' });
    now = new Date('2026-10-18T20:07:00.000Z');
    const again = await checkIns.reply({ checkIn: excuse.id, member: ann, kind: 'approved' });
    expect([again.outcome, again.reply.repliedAt]).toStrictEqual([
      'unchanged',
      new Date('2026-10-18T20:05:00.000Z'),
    ]);
    now = new Date('2026-10-18T20:09:00.000Z');
    const changed = await checkIns.reply({ checkIn: excuse.id, member: ann, kind: 'together' });
    expect(changed.outcome).toBe('changed');
    expect(await checkIns.listReplies({ checkIn: excuse.id, viewer: tracy })).toStrictEqual([
      { member: ann, kind: 'together', repliedAt: new Date('2026-10-18T20:09:00.000Z') },
    ]);
  });

  it('keeps a reply apart from a reaction: a teammate may leave both', async () => {
    const [tracy, ann] = [await newMember(), await newMember()];
    const excuse = await posted('disclaimer', {
      member: tracy,
      audience: [await newSquad(tracy, ann)],
    });

    now = new Date('2026-10-18T20:05:00.000Z');
    await checkIns.reply({ checkIn: excuse.id, member: ann, kind: 'approved' });
    await checkIns.react({ checkIn: excuse.id, member: ann, kind: 'lol' });
    await checkIns.removeReaction({ checkIn: excuse.id, member: ann });
    expect(await checkIns.listReplies({ checkIn: excuse.id, viewer: tracy })).toStrictEqual([
      { member: ann, kind: 'approved', repliedAt: new Date('2026-10-18T20:05:00.000Z') },
    ]);
    await checkIns.react({ checkIn: excuse.id, member: ann, kind: 'lol' });
    await checkIns.removeReply({ checkIn: excuse.id, member: ann });
    expect(
      (await checkIns.listReactions({ checkIn: excuse.id, viewer: tracy })).map(({ kind }) => kind),
    ).toStrictEqual(['lol']);
  });

  it('takes a reply off, and taking it off again is fine', async () => {
    const [tracy, ann] = [await newMember(), await newMember()];
    const excuse = await posted('disclaimer', {
      member: tracy,
      audience: [await newSquad(tracy, ann)],
    });
    await checkIns.reply({ checkIn: excuse.id, member: ann, kind: 'hug' });

    await checkIns.removeReply({ checkIn: excuse.id, member: ann });
    await checkIns.removeReply({ checkIn: excuse.id, member: ann });
    expect(await checkIns.listReplies({ checkIn: excuse.id, viewer: tracy })).toStrictEqual([]);
  });

  it('refuses a reply to your own 请假条, or to a check-in that isn’t one', async () => {
    const [tracy, ann] = [await newMember(), await newMember()];
    const squad = await newSquad(tracy, ann);
    const excuse = await posted('disclaimer', { member: tracy, audience: [squad] });
    const run = await posted('trained', { member: tracy, audience: [squad] });

    await expect(
      checkIns.reply({ checkIn: excuse.id, member: tracy, kind: 'approved' }),
    ).rejects.toStrictEqual(new OwnDisclaimerReplyError());
    await expect(
      checkIns.reply({ checkIn: run.id, member: ann, kind: 'approved' }),
    ).rejects.toStrictEqual(new NotADisclaimerError(run.id));
    expect(await checkIns.listReplies({ checkIn: run.id, viewer: tracy })).toStrictEqual([]);
  });

  it('answers not found for a 请假条 you share no squad on, or that doesn’t exist', async () => {
    const [tracy, ann, stranger] = [await newMember(), await newMember(), await newMember()];
    const ours = await newSquad(tracy, ann);
    // The stranger shares a squad with Tracy, but she didn't send this 请假条 there.
    await newSquad(tracy, stranger);
    const excuse = await posted('disclaimer', { member: tracy, audience: [ours] });
    const missing = CheckInId.parse(randomUUID());

    for (const attempt of [
      () => checkIns.reply({ checkIn: excuse.id, member: stranger, kind: 'approved' }),
      () => checkIns.removeReply({ checkIn: excuse.id, member: stranger }),
      () => checkIns.listReplies({ checkIn: excuse.id, viewer: stranger }),
    ]) {
      await expect(attempt()).rejects.toStrictEqual(new CheckInNotFoundError(excuse.id));
    }
    await expect(
      checkIns.reply({ checkIn: missing, member: ann, kind: 'approved' }),
    ).rejects.toStrictEqual(new CheckInNotFoundError(missing));
  });

  it('shows a teammate only the replies from the squads they share the 请假条 through', async () => {
    const [tracy, ann, bo] = [await newMember(), await newMember(), await newMember()];
    const runners = await newSquad(tracy, ann);
    const climbers = await newSquad(tracy, bo);
    const excuse = await posted('disclaimer', { member: tracy, audience: [runners, climbers] });
    now = new Date('2026-10-18T20:05:00.000Z');
    await checkIns.reply({ checkIn: excuse.id, member: ann, kind: 'approved' });
    now = new Date('2026-10-18T20:06:00.000Z');
    await checkIns.reply({ checkIn: excuse.id, member: bo, kind: 'hug' });

    const annsReply = {
      member: ann,
      kind: 'approved',
      repliedAt: new Date('2026-10-18T20:05:00.000Z'),
    };
    const bosReply = { member: bo, kind: 'hug', repliedAt: new Date('2026-10-18T20:06:00.000Z') };
    expect(await checkIns.listReplies({ checkIn: excuse.id, viewer: ann })).toStrictEqual([
      annsReply,
    ]);
    expect(await checkIns.listReplies({ checkIn: excuse.id, viewer: tracy })).toStrictEqual([
      annsReply,
      bosReply,
    ]);

    // Once Bo leaves the climbers, his reply no longer shows, even to Tracy.
    await leave(climbers, bo);
    expect(await checkIns.listReplies({ checkIn: excuse.id, viewer: tracy })).toStrictEqual([
      annsReply,
    ]);
  });
});
