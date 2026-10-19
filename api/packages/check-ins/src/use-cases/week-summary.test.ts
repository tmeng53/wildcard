import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresCheckInStore,
  type CheckInTables,
} from '../adapters/postgres-check-in-store.js';
import { createPostgresReactionStore } from '../adapters/postgres-reaction-store.js';
import { createPostgresWeeklyPlanStore } from '../adapters/postgres-weekly-plan-store.js';
import { CheckInId, MemberId, SquadId, type CheckInRecord } from '../domain/check-in.js';
import { WeekStart, type PlanDay } from '../domain/weekly-plan.js';
import { createCheckIns } from './check-ins.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<CheckInTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

// Monday 2026-10-26, 1pm in Los Angeles and 5am Tuesday in Tokyo: the week of 10-19 is over.
const now = new Date('2026-10-26T20:00:00.000Z');
// Members' time zones, as the members module would give them.
const zones = new Map<MemberId, string>();
const plans = createPostgresWeeklyPlanStore(db);
/** The check-ins module with its clock at `moment`. */
const checkInsAt = (moment: Date) =>
  createCheckIns({
    store: createPostgresCheckInStore(db),
    reactions: createPostgresReactionStore(db),
    plans,
    photos: { exists: () => Promise.reject(new Error('unused')) },
    calendarOf: (member) => {
      const timeZone = zones.get(member);
      return Promise.resolve(timeZone === undefined ? undefined : { timeZone, joinedAt: moment });
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

/**
 * A check-in written straight to the table, so any day can be used; made at 6pm UTC by default.
 * Returns its id.
 */
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
  return CheckInId.parse(id);
}

/** A teammate's reaction, written straight to the table. */
async function reacted(
  member: MemberId,
  [checkIn, kind]: [CheckInId, 'cheer' | 'highlight' | 'lol'],
) {
  await sql`insert into public.check_in_reactions (check_in_id, member_id, kind, reacted_at)
    values (${checkIn}, ${member}, ${kind}, now())`.execute(db);
}

const week = WeekStart.parse('2026-10-19');
const stats = (values: Record<string, number>) =>
  Object.entries(values).map(([kind, value]) => ({ kind, value }));

describe('a squad’s week summary', () => {
  it('gives the week’s awards, the squad’s totals and the viewer’s own counts', async () => {
    const ace = await newMember('America/Los_Angeles');
    const tokyo = await newMember('Asia/Tokyo');
    const me = await newMember('America/Los_Angeles');
    const quiet = await newMember();
    const leaver = await newMember('America/Los_Angeles');
    const squad = await newSquad(ace, tokyo, me, quiet, leaver);
    const elsewhere = await newSquad(ace);

    // Ace keeps the default plan (5 days) and trains six days, Wednesday twice.
    const aceMonday = await checkedIn(ace, {
      kind: 'trained',
      day: '2026-10-19',
      audience: [squad],
    });
    for (const day of ['2026-10-20', '2026-10-21', '2026-10-21', '2026-10-22', '2026-10-23']) {
      await checkedIn(ace, { kind: 'trained', day, audience: [squad] });
    }
    await checkedIn(ace, { kind: 'trained', day: '2026-10-24', audience: [squad, elsewhere] });
    // Not this week's, or not this squad's.
    await checkedIn(ace, { kind: 'trained', day: '2026-10-18', audience: [squad] });
    await checkedIn(ace, { kind: 'trained', day: '2026-10-25', audience: [elsewhere] });
    // Tokyo plans 3 days and trains all 3.
    await planned(tokyo, {
      monday: '2026-10-19',
      days: [train, train, train, rest, rest, rest, rest],
    });
    for (const day of ['2026-10-19', '2026-10-20', '2026-10-21']) {
      await checkedIn(tokyo, { kind: 'trained', day, audience: [squad] });
    }
    // Me: 2 of 5 days, two 请假条, two meals.
    await checkedIn(me, { kind: 'trained', day: '2026-10-19', audience: [squad] });
    await checkedIn(me, { kind: 'trained', day: '2026-10-20', audience: [squad] });
    const thursday = await checkedIn(me, {
      kind: 'disclaimer',
      day: '2026-10-22',
      audience: [squad],
    });
    const friday = await checkedIn(me, {
      kind: 'disclaimer',
      day: '2026-10-23',
      audience: [squad],
    });
    await checkedIn(me, { kind: 'healthyMeal', day: '2026-10-23', audience: [squad] });
    await checkedIn(me, { kind: 'cheatMeal', day: '2026-10-24', audience: [squad] });

    await reacted(tokyo, [aceMonday, 'cheer']);
    await reacted(me, [aceMonday, 'cheer']);
    await reacted(ace, [thursday, 'lol']);
    await reacted(tokyo, [thursday, 'cheer']);
    await reacted(ace, [friday, 'highlight']);
    await reacted(quiet, [friday, 'lol']);
    // The leaver's reaction would make Friday's the best; they left, so it doesn't count.
    await reacted(leaver, [friday, 'lol']);
    await sql`delete from public.squad_members where squad_id = ${squad} and member_id = ${leaver}`.execute(
      db,
    );

    expect(await checkIns.weekSummary({ viewer: me, squad, weekStart: week })).toStrictEqual({
      from: '2026-10-19',
      to: '2026-10-25',
      final: true,
      awards: [
        {
          kind: 'planCompleted',
          winners: [
            { member: ace, value: 6 },
            { member: tokyo, value: 3 },
          ],
        },
        { kind: 'crown', winners: [{ member: ace, value: 6 }] },
        // Thursday's and Friday's both have 2; Thursday's was posted first.
        { kind: 'bestDisclaimer', winners: [{ member: me, value: 2, checkIn: thursday }] },
      ],
      squad: {
        stats: stats({
          trainedDays: 11,
          plannedDays: 18,
          checkIns: 16,
          disclaimers: 2,
          healthyMeals: 1,
          cheatMeals: 1,
          reactionsReceived: 6,
        }),
        reactions: [
          { kind: 'cheer', count: 3 },
          { kind: 'highlight', count: 1 },
          { kind: 'lol', count: 2 },
        ],
      },
      me: {
        stats: stats({
          trainedDays: 2,
          plannedDays: 5,
          checkIns: 6,
          disclaimers: 2,
          healthyMeals: 1,
          cheatMeals: 1,
          reactionsReceived: 4,
        }),
        reactions: [
          { kind: 'cheer', received: 1, given: 1 },
          { kind: 'highlight', received: 1, given: 0 },
          { kind: 'lol', received: 2, given: 0 },
        ],
      },
    });
  });

  it('shares the crown on a tie, and gives no award nobody won', async () => {
    const one = await newMember('America/Los_Angeles');
    const two = await newMember('America/Los_Angeles');
    const resting = await newMember('America/Los_Angeles');
    const squad = await newSquad(one, two, resting);
    // A week planned all rest, with nothing trained: not on the podium.
    await planned(resting, { monday: '2026-10-19', days: Array.from({ length: 7 }, () => rest) });
    await checkedIn(resting, { kind: 'disclaimer', day: '2026-10-20', audience: [squad] });
    for (const member of [one, two]) {
      await planned(member, {
        monday: '2026-10-19',
        days: [train, train, rest, rest, rest, rest, rest],
      });
      await checkedIn(member, { kind: 'trained', day: '2026-10-19', audience: [squad] });
      await checkedIn(member, { kind: 'trained', day: '2026-10-20', audience: [squad] });
    }

    const summary = await checkIns.weekSummary({ viewer: resting, squad, weekStart: week });
    expect(summary.awards).toStrictEqual([
      {
        kind: 'planCompleted',
        winners: [
          { member: one, value: 2 },
          { member: two, value: 2 },
        ],
      },
      {
        kind: 'crown',
        winners: [
          { member: one, value: 2 },
          { member: two, value: 2 },
        ],
      },
    ]);
  });

  it('is still being played until every member’s Sunday is over', async () => {
    const la = await newMember('America/Los_Angeles');
    const tokyo = await newMember('Asia/Tokyo');
    const squad = await newSquad(la, tokyo);
    // Sunday 1pm in Los Angeles, already Monday 5am in Tokyo.
    const sunday = checkInsAt(new Date('2026-10-25T20:00:00.000Z'));
    expect((await sunday.weekSummary({ viewer: tokyo, squad, weekStart: week })).final).toBe(false);
    // Monday 2:59am in Los Angeles is still Sunday there.
    const lateSunday = checkInsAt(new Date('2026-10-26T09:59:00.000Z'));
    expect((await lateSunday.weekSummary({ viewer: la, squad, weekStart: week })).final).toBe(
      false,
    );
    const monday = checkInsAt(new Date('2026-10-26T10:00:00.000Z'));
    expect((await monday.weekSummary({ viewer: la, squad, weekStart: week })).final).toBe(true);
  });

  it('refuses a week that hasn’t started on the viewer’s clock', async () => {
    const la = await newMember('America/Los_Angeles');
    const squad = await newSquad(la);
    // Sunday 9pm in Los Angeles: next week hasn't started, though it has in UTC.
    const sundayNight = checkInsAt(new Date('2026-10-26T04:00:00.000Z'));
    await expect(
      sundayNight.weekSummary({ viewer: la, squad, weekStart: WeekStart.parse('2026-10-26') }),
    ).rejects.toMatchObject({ reason: 'WEEK_NOT_STARTED' });
    const summary = await sundayNight.weekSummary({ viewer: la, squad, weekStart: week });
    expect(summary).toMatchObject({ final: false, awards: [] });
  });

  it('shows a squad’s week only to its members', async () => {
    const member = await newMember('America/Los_Angeles');
    const outsider = await newMember('America/Los_Angeles');
    const squad = await newSquad(member);
    await expect(
      checkIns.weekSummary({ viewer: outsider, squad, weekStart: week }),
    ).rejects.toMatchObject({ reason: 'SQUAD_NOT_JOINED' });
  });
});
