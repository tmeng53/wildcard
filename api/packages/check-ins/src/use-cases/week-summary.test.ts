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
import { createPostgresReplyStore } from '../adapters/postgres-reply-store.js';
import { createPostgresWeeklyPlanStore } from '../adapters/postgres-weekly-plan-store.js';
import { CheckInId, MemberId, SquadId, type CheckInRecord } from '../domain/check-in.js';
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

// Monday 2026-10-26, 1pm in Los Angeles and 5am Tuesday in Tokyo: the week of 10-19 is over.
const now = new Date('2026-10-26T20:00:00.000Z');
// Members' time zones, as the members module would give them.
const zones = new Map<MemberId, string>();
const plans = createPostgresWeeklyPlanStore(db);
/** When every member joined: weeks before the weeks tested. */
const JOINED = new Date('2026-09-01T00:00:00.000Z');

/** The check-ins module with its clock at `moment`. */
const checkInsAt = (moment: Date, joinedAt = JOINED) =>
  createCheckIns({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresCheckInStore(db),
    membership,
    reactions: createPostgresReactionStore(db),
    replies: createPostgresReplyStore(db),
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

/** A teammate's reaction, written straight to the table; left now unless `at` says when. */
async function reacted(member: MemberId, [checkIn, emoji, at]: [CheckInId, string, Date?]) {
  const reactedAt = (at ?? new Date()).toISOString();
  await sql`insert into public.check_in_reactions (check_in_id, member_id, emoji, reacted_at)
    values (${checkIn}, ${member}, ${emoji}, ${reactedAt})`.execute(db);
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

    await reacted(tokyo, [aceMonday, '❤️']);
    await reacted(me, [aceMonday, '❤️']);
    await reacted(ace, [thursday, '😂']);
    await reacted(tokyo, [thursday, '❤️']);
    await reacted(ace, [friday, '💪']);
    await reacted(quiet, [friday, '😂']);
    // The leaver's reaction would make Friday's the best; they left, so it doesn't count.
    await reacted(leaver, [friday, '😂']);
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
          { emoji: '❤️', count: 3 },
          { emoji: '😂', count: 2 },
          { emoji: '💪', count: 1 },
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
          { emoji: '😂', received: 2, given: 0 },
          { emoji: '❤️', received: 1, given: 1 },
          { emoji: '💪', received: 1, given: 0 },
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

  it('counts the planned days from the day a member joined', async () => {
    // Joined on Thursday morning in Los Angeles: the default plan's Thursday to Saturday count.
    const joinedThursday = checkInsAt(now, new Date('2026-10-22T16:00:00.000Z'));
    const la = await newMember('America/Los_Angeles');
    const squad = await newSquad(la);
    const summary = await joinedThursday.weekSummary({ viewer: la, squad, weekStart: week });
    const planned = (rows: readonly { kind: string; value: number }[]) =>
      rows.find(({ kind }) => kind === 'plannedDays')?.value;
    expect([planned(summary.me.stats), planned(summary.squad.stats)]).toStrictEqual([3, 3]);
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

describe('a squad’s week for its awards', () => {
  const before = new Date('2026-10-25T12:00:00.000Z');

  it('gives the 战报’s pages from the check-ins and reactions made before the awards', async () => {
    const ace = await newMember('America/Los_Angeles');
    const tokyo = await newMember('Asia/Tokyo');
    const me = await newMember('America/Los_Angeles');
    const quiet = await newMember();
    const squad = await newSquad(ace, tokyo, me, quiet);

    // Ace keeps the default plan (rest on Wednesday and Sunday) and trains its 5 days.
    for (const day of ['2026-10-19', '2026-10-20', '2026-10-22', '2026-10-23', '2026-10-24']) {
      await checkedIn(ace, { kind: 'trained', day, audience: [squad] });
    }
    // Tokyo plans 3 days and trains all 3.
    await planned(tokyo, {
      monday: '2026-10-19',
      days: [train, train, train, rest, rest, rest, rest],
    });
    for (const day of ['2026-10-19', '2026-10-20', '2026-10-21']) {
      await checkedIn(tokyo, { kind: 'trained', day, audience: [squad] });
    }
    // Me: one day trained, a 请假条, a 健康餐 and two 放纵餐; Sunday's 练了 comes after the awards.
    await checkedIn(me, { kind: 'trained', day: '2026-10-19', audience: [squad] });
    const note = await checkedIn(me, { kind: 'disclaimer', day: '2026-10-21', audience: [squad] });
    await checkedIn(me, { kind: 'healthyMeal', day: '2026-10-22', audience: [squad] });
    await checkedIn(me, { kind: 'cheatMeal', day: '2026-10-23', audience: [squad] });
    await checkedIn(me, { kind: 'cheatMeal', day: '2026-10-24', audience: [squad] });
    await checkedIn(me, { kind: 'trained', day: '2026-10-25', audience: [squad] });
    await reacted(ace, [note, '😂', new Date('2026-10-24T00:00:00.000Z')]);
    // Tokyo's reaction comes after the awards: it doesn't count.
    await reacted(tokyo, [note, '❤️']);

    const { pages } = await checkIns.squadWeekCheckIns({
      squad,
      weekStart: week,
      before,
      members: [ace, tokyo, me, quiet],
    });
    const days = (...kinds: string[]) =>
      kinds.map((kind, index) => ({
        day: `2026-10-${String(19 + index)}`,
        ...(kind === 'run' ? { kind: 'trained', sport: 'run' } : { kind }),
      }));
    expect(pages).toStrictEqual({
      podium: { champion: ace, sides: [tokyo] },
      members: [
        {
          member: ace,
          plannedDays: 5,
          trainedDays: 5,
          days: days('run', 'run', 'rest', 'run', 'run', 'run', 'rest'),
          healthyMeals: 0,
          cheatMeals: 0,
          reactionsReceived: 0,
          checkedIn: true,
        },
        {
          member: tokyo,
          plannedDays: 3,
          trainedDays: 3,
          days: days('run', 'run', 'run', 'rest', 'rest', 'rest', 'rest'),
          healthyMeals: 0,
          cheatMeals: 0,
          reactionsReceived: 0,
          checkedIn: true,
        },
        {
          member: me,
          plannedDays: 5,
          trainedDays: 1,
          days: days('run', 'none', 'disclaimer', 'none', 'none', 'none', 'rest'),
          healthyMeals: 1,
          cheatMeals: 2,
          reactionsReceived: 1,
          checkedIn: true,
        },
        {
          member: quiet,
          plannedDays: 5,
          trainedDays: 0,
          days: days('none', 'none', 'rest', 'none', 'none', 'none', 'rest'),
          healthyMeals: 0,
          cheatMeals: 0,
          reactionsReceived: 0,
          checkedIn: false,
        },
      ],
      meals: { healthy: 1, cheat: 2, eaters: [{ member: me, more: 'cheat' }] },
      bestDisclaimer: { checkIn: note, author: me, text: '下雨', reactions: 1 },
      ending: { done: 9, plan: 18 },
    });
  });

  it('leaves out the pages a quiet week has nothing for', async () => {
    const quiet = await newMember();
    const squad = await newSquad(quiet);
    const { pages } = await checkIns.squadWeekCheckIns({
      squad,
      weekStart: week,
      before,
      members: [quiet],
    });
    expect(Object.keys(pages)).toStrictEqual(['members']);
  });
});
