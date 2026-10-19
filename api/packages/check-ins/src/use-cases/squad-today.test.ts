import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresCheckInStore,
  type CheckInTables,
} from '../adapters/postgres-check-in-store.js';
import { MemberId, SquadId, type CheckInRecord } from '../domain/check-in.js';
import { createCheckIns } from './check-ins.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<CheckInTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

// Wednesday 2026-10-21, 1pm in Los Angeles and already 5am Thursday in Tokyo.
const now = new Date('2026-10-21T20:00:00.000Z');
// Members' time zones, as the members module would give them.
const zones = new Map<MemberId, string>();
const checkIns = createCheckIns({
  store: createPostgresCheckInStore(db),
  photos: { exists: () => Promise.reject(new Error('unused')) },
  calendarOf: (member) => {
    const timeZone = zones.get(member);
    return Promise.resolve(timeZone === undefined ? undefined : { timeZone, joinedAt: now });
  },
  clock: () => now,
});

async function newMember(timeZone?: string) {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  if (timeZone !== undefined) zones.set(id, timeZone);
  return id;
}

/** A squad its members joined in the order given, a minute apart. */
async function newSquad(...members: MemberId[]) {
  const id = SquadId.parse(randomUUID());
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${id})`.execute(
    db,
  );
  for (const [index, member] of members.entries()) {
    const joinedAt = new Date(Date.UTC(2026, 9, 1, 0, index)).toISOString();
    await sql`insert into public.squad_members (squad_id, member_id, joined_at)
      values (${id}, ${member}, ${joinedAt})`.execute(db);
  }
  return id;
}

const payloads: Record<CheckInRecord['kind'], object> = {
  trained: { version: 1, sport: 'run' },
  healthyMeal: { version: 1 },
  cheatMeal: { version: 1 },
  disclaimer: { version: 1, text: '下雨' },
};

/** A check-in written straight to the table, so any day can be used; made at 6pm UTC by default. */
async function checkedIn(
  member: MemberId,
  {
    kind,
    day,
    audience,
    hour = 18,
  }: {
    readonly kind: CheckInRecord['kind'];
    readonly day: string;
    readonly audience: readonly SquadId[];
    readonly hour?: number;
  },
) {
  const id = randomUUID();
  const createdAt = `${day}T${String(hour).padStart(2, '0')}:00:00.000Z`;
  await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
    values (${id}, ${member}, ${day}, ${createdAt}, ${kind}, ${JSON.stringify(payloads[kind])})`.execute(
    db,
  );
  for (const [index, squad] of audience.entries()) {
    await sql`insert into public.check_in_squads (check_in_id, squad_id, position)
      values (${id}, ${squad}, ${index + 1})`.execute(db);
  }
}

describe('a squad’s today', () => {
  it('gives each member’s own today and the week’s counts', async () => {
    const me = await newMember('America/Los_Angeles');
    const tokyo = await newMember('Asia/Tokyo');
    const noZone = await newMember();
    const leaver = await newMember('America/Los_Angeles');
    const squad = await newSquad(me, tokyo, noZone, leaver);
    const elsewhere = await newSquad(me);

    // Me: last Sunday, Monday twice, Tuesday to another squad, then a 免责 and a 练了 today.
    await checkedIn(me, { kind: 'trained', day: '2026-10-18', audience: [squad] });
    await checkedIn(me, { kind: 'trained', day: '2026-10-19', audience: [squad] });
    await checkedIn(me, { kind: 'trained', day: '2026-10-19', audience: [squad, elsewhere] });
    await checkedIn(me, { kind: 'trained', day: '2026-10-20', audience: [elsewhere] });
    await checkedIn(me, { kind: 'disclaimer', day: '2026-10-21', audience: [squad], hour: 17 });
    await checkedIn(me, { kind: 'trained', day: '2026-10-21', audience: [squad], hour: 19 });
    // Tokyo is on Thursday: trained Tuesday, and a 免责 today.
    await checkedIn(tokyo, { kind: 'trained', day: '2026-10-20', audience: [squad] });
    await checkedIn(tokyo, { kind: 'disclaimer', day: '2026-10-22', audience: [squad] });
    await checkedIn(tokyo, { kind: 'trained', day: '2026-10-21', audience: [elsewhere] });
    // No zone saved: read on my clock. Two meals today, the 放纵餐 last.
    await checkedIn(noZone, {
      kind: 'healthyMeal',
      day: '2026-10-21',
      audience: [squad],
      hour: 17,
    });
    await checkedIn(noZone, { kind: 'cheatMeal', day: '2026-10-21', audience: [squad], hour: 19 });
    // Someone who trained and then left: not in the squad, not counted.
    await checkedIn(leaver, { kind: 'trained', day: '2026-10-21', audience: [squad] });
    await sql`delete from public.squad_members where squad_id = ${squad} and member_id = ${leaver}`.execute(
      db,
    );

    expect(await checkIns.squadToday({ viewer: me, squad })).toStrictEqual({
      members: [
        { member: me, day: '2026-10-21', training: 'trained', latestMeal: undefined },
        { member: tokyo, day: '2026-10-22', training: 'disclaimer', latestMeal: undefined },
        { member: noZone, day: '2026-10-21', training: 'notCheckedIn', latestMeal: 'cheatMeal' },
      ],
      trainedToday: 1,
      disclaimerToday: 1,
      everyoneTrained: false,
      myWeek: {
        from: '2026-10-19',
        to: '2026-10-25',
        days: [
          '2026-10-19',
          '2026-10-20',
          '2026-10-21',
          '2026-10-22',
          '2026-10-23',
          '2026-10-24',
          '2026-10-25',
        ],
        trainedDays: 3,
      },
      myLifetimeTrainedDays: 4,
      // Me: Monday and today (Tuesday went elsewhere). Tokyo: Tuesday.
      squadTrainedDays: 3,
    });
  });

  it('says when everyone has trained', async () => {
    const me = await newMember('America/Los_Angeles');
    const friend = await newMember('America/New_York');
    const squad = await newSquad(me, friend);
    await checkedIn(me, { kind: 'trained', day: '2026-10-21', audience: [squad] });
    expect((await checkIns.squadToday({ viewer: friend, squad })).everyoneTrained).toBe(false);
    await checkedIn(friend, { kind: 'trained', day: '2026-10-21', audience: [squad] });
    const today = await checkIns.squadToday({ viewer: friend, squad });
    expect([today.everyoneTrained, today.trainedToday, today.myLifetimeTrainedDays]).toStrictEqual([
      true,
      2,
      1,
    ]);
  });

  it('shows a squad only to its members', async () => {
    const member = await newMember('America/Los_Angeles');
    const outsider = await newMember('America/Los_Angeles');
    const squad = await newSquad(member);
    await expect(checkIns.squadToday({ viewer: outsider, squad })).rejects.toMatchObject({
      reason: 'SQUAD_NOT_JOINED',
    });
    await expect(
      checkIns.squadToday({ viewer: member, squad: SquadId.parse(randomUUID()) }),
    ).rejects.toMatchObject({ reason: 'SQUAD_NOT_JOINED' });
  });
});
