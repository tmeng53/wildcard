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
import { MemberId, SquadId, type CheckInRecord } from '../domain/check-in.js';
import { WeekStart, type PlanDay } from '../domain/weekly-plan.js';
import { createCheckIns } from './check-ins.js';

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

// Wednesday 2026-10-21, 1pm in Los Angeles and already 5am Thursday in Tokyo.
const now = new Date('2026-10-21T20:00:00.000Z');
// Members' time zones, as the members module would give them.
const zones = new Map<MemberId, string>();
const plans = createPostgresWeeklyPlanStore(db);
/** When every member joined unless a test says otherwise: weeks before the weeks tested. */
const JOINED = new Date('2026-09-01T00:00:00.000Z');

/** The check-ins module with its clock at `moment`. */
const checkInsAt = (moment: Date, joinedAt = JOINED) =>
  createCheckIns({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresCheckInStore(db),
    membership,
    reactions: createPostgresReactionStore(db),
    comments: createPostgresCommentStore(db),
    plans,
    photos: { exists: () => Promise.reject(new Error('unused')) },
    calendarOf: (member) => {
      const timeZone = zones.get(member);
      return Promise.resolve(timeZone === undefined ? undefined : { timeZone, joinedAt });
    },
    clock: () => moment,
  });
const checkIns = checkInsAt(now);

const train: PlanDay = { kind: 'train' };
const rest: PlanDay = { kind: 'rest' };
/** Saves the member's plan for the week from `monday`, days Monday first. */
async function planned(member: MemberId, { monday, days }: { monday: string; days: PlanDay[] }) {
  await plans.save({ member, weekStart: WeekStart.parse(monday), days });
}

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

    // Me: last Sunday, Monday twice, Tuesday to another squad, then a 请假条 and a 练了 today.
    await checkedIn(me, { kind: 'trained', day: '2026-10-18', audience: [squad] });
    await checkedIn(me, { kind: 'trained', day: '2026-10-19', audience: [squad] });
    await checkedIn(me, { kind: 'trained', day: '2026-10-19', audience: [squad, elsewhere] });
    await checkedIn(me, { kind: 'trained', day: '2026-10-20', audience: [elsewhere] });
    await checkedIn(me, { kind: 'disclaimer', day: '2026-10-21', audience: [squad], hour: 17 });
    await checkedIn(me, { kind: 'trained', day: '2026-10-21', audience: [squad], hour: 19 });
    // Tokyo is on Thursday: trained Tuesday, and a 请假条 today.
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

    // Tokyo rests on Thursdays and weekends: 4 training days. The others have the default plan
    // (rest on Wednesday and Sunday, 5 training days), so today is a rest day for me and noZone.
    await planned(tokyo, {
      monday: '2026-10-19',
      days: [train, train, train, rest, train, rest, rest],
    });

    expect(await checkIns.squadToday({ viewer: me, squad })).toStrictEqual({
      // Checked in today, by first check-in: me and noZone both at 17:00 (join order), then Tokyo.
      members: [
        {
          member: me,
          day: '2026-10-21',
          training: 'trained',
          latestMeal: undefined,
          plannedRest: true,
          firstCheckInAt: new Date('2026-10-21T17:00:00.000Z'),
        },
        {
          member: noZone,
          day: '2026-10-21',
          training: 'notCheckedIn',
          latestMeal: 'cheatMeal',
          plannedRest: true,
          firstCheckInAt: new Date('2026-10-21T17:00:00.000Z'),
        },
        {
          member: tokyo,
          day: '2026-10-22',
          training: 'disclaimer',
          latestMeal: undefined,
          plannedRest: true,
          firstCheckInAt: new Date('2026-10-22T18:00:00.000Z'),
        },
      ],
      trainedToday: 1,
      disclaimerToday: 1,
      // noZone: a rest day with only meals.
      restingToday: 1,
      // Me trained; noZone and Tokyo are on planned rest days, Tokyo with a 请假条.
      everyoneTrained: true,
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
        plannedDays: 5,
      },
      myLifetimeTrainedDays: 4,
      // Trained: me on Monday and today (Tuesday went elsewhere), Tokyo on Tuesday.
      // Planned: 5 + 4 + 5.
      squadWeek: { trainedDays: 3, plannedDays: 14 },
    });
  });

  it('says when everyone has trained', async () => {
    const me = await newMember('America/Los_Angeles');
    const friend = await newMember('America/New_York');
    const squad = await newSquad(me, friend);
    // Today, Wednesday, is a training day for both.
    for (const member of [me, friend]) {
      await planned(member, {
        monday: '2026-10-19',
        days: [train, train, train, train, train, rest, rest],
      });
    }
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

  it('needs someone to train for 全员上场, not only rest', async () => {
    // Both keep the default plan, so today, Wednesday, is a rest day for both.
    const me = await newMember('America/Los_Angeles');
    const friend = await newMember('America/Los_Angeles');
    const squad = await newSquad(me, friend);
    const resting = await checkIns.squadToday({ viewer: me, squad });
    expect([resting.everyoneTrained, resting.restingToday, resting.trainedToday]).toStrictEqual([
      false,
      2,
      0,
    ]);
    await checkedIn(friend, { kind: 'trained', day: '2026-10-21', audience: [squad] });
    const trained = await checkIns.squadToday({ viewer: me, squad });
    expect([trained.everyoneTrained, trained.restingToday, trained.trainedToday]).toStrictEqual([
      true,
      1,
      1,
    ]);
  });

  it('reads each member in their own week, and counts a planned rest as on the field', async () => {
    // Sunday 9pm in Los Angeles, already Monday 1pm of the next week in Tokyo.
    const sundayNight = checkInsAt(new Date('2026-10-26T04:00:00.000Z'));
    const la = await newMember('America/Los_Angeles');
    const tokyo = await newMember('Asia/Tokyo');
    const squad = await newSquad(la, tokyo);
    await checkedIn(la, { kind: 'trained', day: '2026-10-24', audience: [squad] });
    // Saturday is Tokyo's last week; Monday is this week.
    await checkedIn(tokyo, { kind: 'trained', day: '2026-10-24', audience: [squad] });
    await checkedIn(tokyo, { kind: 'trained', day: '2026-10-26', audience: [squad], hour: 2 });
    // Tokyo's typical week, made last week: 4 training days, Monday a training day.
    await plans.saveTemplate({
      member: tokyo,
      fromWeek: WeekStart.parse('2026-10-19'),
      days: [train, train, train, rest, train, rest, rest],
    });

    const today = await sundayNight.squadToday({ viewer: la, squad });
    expect(today.members.map(({ member, day, plannedRest }) => [member, day, plannedRest])).toEqual(
      [
        [tokyo, '2026-10-26', false],
        // Sunday is a rest day in the default plan.
        [la, '2026-10-25', true],
      ],
    );
    expect(today).toMatchObject({
      trainedToday: 1,
      restingToday: 1,
      everyoneTrained: true,
      myWeek: { from: '2026-10-19', to: '2026-10-25', trainedDays: 1, plannedDays: 5 },
      // LA: Saturday. Tokyo: Monday only, since Saturday was in Tokyo's last week. Planned: 5 + 4.
      squadWeek: { trainedDays: 2, plannedDays: 9 },
    });
  });

  it('counts the planned days from the day a member joined', async () => {
    // Joined today, Wednesday: the default plan's Thursday to Saturday are left to train.
    const joinedToday = checkInsAt(now, now);
    const me = await newMember('America/Los_Angeles');
    const squad = await newSquad(me);
    const today = await joinedToday.squadToday({ viewer: me, squad });
    expect([today.myWeek.plannedDays, today.squadWeek.plannedDays]).toStrictEqual([3, 3]);
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
