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
import { createPostgresReactionStore } from '../adapters/postgres-reaction-store.js';
import { createPostgresWeeklyPlanStore } from '../adapters/postgres-weekly-plan-store.js';
import { CheckInDraft, CheckInId, MemberId, SquadId } from '../domain/check-in.js';
import { Emoji } from '../domain/reaction.js';
import { CheckInNotFoundError, OwnCheckInReactionError } from '../errors.js';
import { createCheckIns } from './check-ins.js';

const heart = Emoji.parse('❤️');
const muscle = Emoji.parse('💪');
const laughing = Emoji.parse('😂');

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

async function leave(squad: SquadId, member: MemberId) {
  await sql`delete from public.squad_members where squad_id = ${squad} and member_id = ${member}`.execute(
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

describe('reacting to a check-in', () => {
  it('leaves a teammate’s reaction, which the author and teammates can read', async () => {
    const [tracy, ann, bo] = [await newMember(), await newMember(), await newMember()];
    const squad = await newSquad(tracy, ann, bo);
    const run = await trained(tracy, squad);

    now = new Date('2026-10-18T20:05:00.000Z');
    const reacted = await checkIns.react({ checkIn: run.id, member: ann, emoji: heart });
    expect([reacted.outcome, reacted.reaction]).toStrictEqual([
      'created',
      { member: ann, emoji: heart, reactedAt: new Date('2026-10-18T20:05:00.000Z') },
    ]);
    now = new Date('2026-10-18T20:06:00.000Z');
    await checkIns.react({ checkIn: run.id, member: bo, emoji: muscle });

    const expected = [
      { member: ann, emoji: heart, reactedAt: new Date('2026-10-18T20:05:00.000Z') },
      { member: bo, emoji: muscle, reactedAt: new Date('2026-10-18T20:06:00.000Z') },
    ];
    expect(await checkIns.listReactions({ checkIn: run.id, viewer: tracy })).toStrictEqual(
      expected,
    );
    expect(await checkIns.listReactions({ checkIn: run.id, viewer: bo })).toStrictEqual(expected);
  });

  it('keeps one reaction per member: a different one replaces it, the same one changes nothing', async () => {
    const [tracy, ann] = [await newMember(), await newMember()];
    const run = await trained(tracy, await newSquad(tracy, ann));

    now = new Date('2026-10-18T20:05:00.000Z');
    await checkIns.react({ checkIn: run.id, member: ann, emoji: heart });
    now = new Date('2026-10-18T20:07:00.000Z');
    const again = await checkIns.react({ checkIn: run.id, member: ann, emoji: heart });
    expect([again.outcome, again.reaction.reactedAt]).toStrictEqual([
      'unchanged',
      new Date('2026-10-18T20:05:00.000Z'),
    ]);
    now = new Date('2026-10-18T20:09:00.000Z');
    const changed = await checkIns.react({ checkIn: run.id, member: ann, emoji: laughing });
    expect(changed.outcome).toBe('changed');
    expect(await checkIns.listReactions({ checkIn: run.id, viewer: tracy })).toStrictEqual([
      { member: ann, emoji: laughing, reactedAt: new Date('2026-10-18T20:09:00.000Z') },
    ]);
  });

  it('takes a reaction off, and taking it off again is fine', async () => {
    const [tracy, ann] = [await newMember(), await newMember()];
    const run = await trained(tracy, await newSquad(tracy, ann));
    await checkIns.react({ checkIn: run.id, member: ann, emoji: heart });

    await checkIns.removeReaction({ checkIn: run.id, member: ann });
    await checkIns.removeReaction({ checkIn: run.id, member: ann });
    expect(await checkIns.listReactions({ checkIn: run.id, viewer: tracy })).toStrictEqual([]);
  });

  it('refuses a reaction on your own check-in', async () => {
    const tracy = await newMember();
    const run = await trained(tracy, await newSquad(tracy));
    await expect(
      checkIns.react({ checkIn: run.id, member: tracy, emoji: heart }),
    ).rejects.toStrictEqual(new OwnCheckInReactionError());
  });

  it('answers not found for a check-in you share no squad on, or that doesn’t exist', async () => {
    const [tracy, ann, stranger] = [await newMember(), await newMember(), await newMember()];
    const ours = await newSquad(tracy, ann);
    // The stranger shares a squad with Tracy, but she didn't send this check-in there.
    await newSquad(tracy, stranger);
    const run = await trained(tracy, ours);
    const missing = CheckInId.parse(randomUUID());

    for (const attempt of [
      () => checkIns.react({ checkIn: run.id, member: stranger, emoji: heart }),
      () => checkIns.removeReaction({ checkIn: run.id, member: stranger }),
      () => checkIns.listReactions({ checkIn: run.id, viewer: stranger }),
    ]) {
      await expect(attempt()).rejects.toStrictEqual(new CheckInNotFoundError(run.id));
    }
    await expect(
      checkIns.react({ checkIn: missing, member: ann, emoji: heart }),
    ).rejects.toStrictEqual(new CheckInNotFoundError(missing));
  });

  it('stops a member who left the squad, or whose author left it, from reacting', async () => {
    const [tracy, ann, bo] = [await newMember(), await newMember(), await newMember()];
    const squad = await newSquad(tracy, ann, bo);
    const run = await trained(tracy, squad);

    await leave(squad, ann);
    await expect(
      checkIns.react({ checkIn: run.id, member: ann, emoji: heart }),
    ).rejects.toBeInstanceOf(CheckInNotFoundError);
    await join(squad, ann);
    await leave(squad, tracy);
    await expect(
      checkIns.react({ checkIn: run.id, member: bo, emoji: heart }),
    ).rejects.toBeInstanceOf(CheckInNotFoundError);
  });
});

describe('who sees which reactions', () => {
  it('shows a teammate only reactions from the squads they share the check-in through', async () => {
    const [tracy, ann, bo] = [await newMember(), await newMember(), await newMember()];
    // Ann is in the runners only, Bo in the climbers only; Tracy sends to both.
    const runners = await newSquad(tracy, ann);
    const climbers = await newSquad(tracy, bo);
    const run = await trained(tracy, runners, climbers);
    now = new Date('2026-10-18T20:05:00.000Z');
    await checkIns.react({ checkIn: run.id, member: ann, emoji: heart });
    now = new Date('2026-10-18T20:06:00.000Z');
    await checkIns.react({ checkIn: run.id, member: bo, emoji: laughing });

    const annsReaction = {
      member: ann,
      emoji: heart,
      reactedAt: new Date('2026-10-18T20:05:00.000Z'),
    };
    const bosReaction = {
      member: bo,
      emoji: laughing,
      reactedAt: new Date('2026-10-18T20:06:00.000Z'),
    };
    expect(await checkIns.listReactions({ checkIn: run.id, viewer: ann })).toStrictEqual([
      annsReaction,
    ]);
    expect(await checkIns.listReactions({ checkIn: run.id, viewer: bo })).toStrictEqual([
      bosReaction,
    ]);
    expect(await checkIns.listReactions({ checkIn: run.id, viewer: tracy })).toStrictEqual([
      annsReaction,
      bosReaction,
    ]);

    // Once Bo leaves the climbers, his reaction no longer shows, even to Tracy.
    await leave(climbers, bo);
    expect(await checkIns.listReactions({ checkIn: run.id, viewer: tracy })).toStrictEqual([
      annsReaction,
    ]);
  });

  it('lists each post in a squad’s feed with the reactions its viewer may see', async () => {
    const [tracy, ann, bo] = [await newMember(), await newMember(), await newMember()];
    const runners = await newSquad(tracy, ann);
    const climbers = await newSquad(tracy, bo);
    const run = await trained(tracy, runners, climbers);
    const quiet = await trained(ann, runners);
    now = new Date('2026-10-18T20:05:00.000Z');
    await checkIns.react({ checkIn: run.id, member: ann, emoji: heart });
    now = new Date('2026-10-18T20:06:00.000Z');
    await checkIns.react({ checkIn: run.id, member: bo, emoji: laughing });
    const days = { from: '2026-10-18', to: '2026-10-18' };
    const feed = async (viewer: MemberId, squad: SquadId) =>
      (await checkIns.listForSquad({ viewer, squad, days })).map(({ checkIn, reactions }) => ({
        id: checkIn.id,
        emoji: reactions.map(({ member, emoji }) => [member, emoji]),
      }));

    // Ann sees the runners' feed, so only her own heart on Tracy's run; Tracy sees both.
    const annSees = [
      { id: run.id, emoji: [[ann, heart]] },
      { id: quiet.id, emoji: [] },
    ];
    expect(new Set(await feed(ann, runners))).toStrictEqual(new Set(annSees));
    expect(await feed(tracy, climbers)).toStrictEqual([
      {
        id: run.id,
        emoji: [
          [ann, heart],
          [bo, laughing],
        ],
      },
    ]);
    // Each post's reactions are the same as reading them one post at a time.
    for (const viewer of [tracy, ann]) {
      for (const { checkIn, reactions } of await checkIns.listForSquad({
        viewer,
        squad: runners,
        days,
      })) {
        expect(reactions).toStrictEqual(
          await checkIns.listReactions({ checkIn: checkIn.id, viewer }),
        );
      }
    }
  });
});
