import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import type { CheckInTables } from '../adapters/postgres-check-in-store.js';
import { createPostgresWeeklyPlanStore } from '../adapters/postgres-weekly-plan-store.js';
import { MemberId } from '../domain/check-in.js';
import { WeekStart, type PlanDays } from '../domain/weekly-plan.js';
import {
  PlanDayStartedError,
  RestDaysFixedError,
  TimeZoneNotSetError,
  WeekOverError,
  WeekStartedError,
} from '../errors.js';
import { createWeeklyPlans } from './weekly-plans.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<CheckInTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

// Wednesday 2026-10-21, 13:00 in Los Angeles.
let now = new Date('2026-10-21T20:00:00.000Z');
// Members' time zones and when they joined: their profiles, which the members module keeps.
const calendars = new Map<string, { timeZone: string; joinedAt: Date }>();
const plans = createWeeklyPlans({
  store: createPostgresWeeklyPlanStore(db),
  calendarOf: (member) => Promise.resolve(calendars.get(member)),
  clock: () => now,
});

/** A member who joined today, unless `joinedAt` says when. */
async function newMember({
  timeZone = 'America/Los_Angeles',
  joinedAt = new Date('2026-10-21T17:00:00.000Z'),
} = {}) {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  calendars.set(id, { timeZone, joinedAt });
  return id;
}

const week = (monday: string) => WeekStart.parse(monday);
const thisWeek = week('2026-10-19');
const lastWeek = week('2026-10-12');
const nextWeek = week('2026-10-26');

/** What every week of a member who joined this week, without 饮食小目标, adds to its plan. */
const joinedThisWeek = { fuelGoals: [], firstWeek: '2026-10-19' };

const train = { kind: 'train' } as const;
const rest = { kind: 'rest' } as const;
const swim = { kind: 'train', sport: 'swim' } as const;
// Rest on Tuesday and Saturday.
const mine: PlanDays = [swim, rest, train, train, train, rest, train];

async function storedRows(member: MemberId) {
  const { rows } = await sql<{ week_start: string; payload: unknown }>`
    select week_start::text, payload from weekly_plans where member_id = ${member} order by week_start
  `.execute(db);
  return rows;
}

describe('reading a week’s plan', () => {
  it('gives the default, rest on Wednesday and Sunday, before the first save', async () => {
    const member = await newMember();
    expect(await plans.find({ member, weekStart: thisWeek })).toStrictEqual({
      weekStart: '2026-10-19',
      days: [train, train, rest, train, train, train, rest],
      source: 'default',
      ...joinedThisWeek,
    });
  });

  it('carries the latest saved plan into later weeks, but not earlier ones', async () => {
    const member = await newMember();
    await plans.save({ member, weekStart: thisWeek, days: mine });
    expect(await plans.find({ member, weekStart: thisWeek })).toStrictEqual({
      weekStart: '2026-10-19',
      days: mine,
      source: 'saved',
      ...joinedThisWeek,
    });
    expect(await plans.find({ member, weekStart: week('2026-11-09') })).toStrictEqual({
      weekStart: '2026-11-09',
      days: mine,
      source: 'carriedOver',
      ...joinedThisWeek,
    });
    expect((await plans.find({ member, weekStart: lastWeek })).source).toBe('default');
  });

  it('keeps each member’s plan to themselves', async () => {
    const tracy = await newMember();
    const friend = await newMember();
    await plans.save({ member: tracy, weekStart: thisWeek, days: mine });
    expect((await plans.find({ member: friend, weekStart: thisWeek })).source).toBe('default');
  });
});

describe('saving a week’s plan', () => {
  it('stores it as versioned JSON, once per week, and a repeat changes nothing', async () => {
    const member = await newMember();
    const saved = { weekStart: '2026-10-19', days: mine, source: 'saved', ...joinedThisWeek };
    expect(await plans.save({ member, weekStart: thisWeek, days: mine })).toStrictEqual(saved);
    expect(await plans.save({ member, weekStart: thisWeek, days: mine })).toStrictEqual(saved);
    expect(await storedRows(member)).toStrictEqual([
      { week_start: '2026-10-19', payload: { version: 1, days: mine } },
    ]);
  });

  it('logs each saved change, in order, and never a save that changed nothing', async () => {
    const member = await newMember();
    const swapped: PlanDays = [swim, rest, train, train, train, train, rest];
    await plans.save({ member, weekStart: thisWeek, days: mine });
    await plans.save({ member, weekStart: thisWeek, days: mine });
    await plans.save({ member, weekStart: nextWeek, days: mine });
    await plans.save({ member, weekStart: thisWeek, days: swapped });
    const { rows } = await sql<{ week_start: string; payload: unknown }>`
      select week_start::text, payload from weekly_plan_events where member_id = ${member} order by id
    `.execute(db);
    expect(rows).toStrictEqual([
      { week_start: '2026-10-19', payload: { version: 1, days: mine } },
      { week_start: '2026-10-26', payload: { version: 1, days: mine } },
      { week_start: '2026-10-19', payload: { version: 1, days: swapped } },
    ]);
  });

  it('lets a member who signs up mid-week plan the whole week that day', async () => {
    const member = await newMember();
    const days: PlanDays = [rest, rest, rest, train, train, train, train];
    expect((await plans.save({ member, weekStart: thisWeek, days })).days).toStrictEqual(days);
  });

  it('keeps the days since a member joined, even on the default plan', async () => {
    // Joined weeks ago and never planned: Monday and Tuesday can't turn into rest days now.
    const longAgo = await newMember({ joinedAt: new Date('2026-09-01T17:00:00.000Z') });
    await expect(
      plans.save({
        member: longAgo,
        weekStart: thisWeek,
        days: [rest, rest, rest, train, train, train, train],
      }),
    ).rejects.toThrow(new PlanDayStartedError('2026-10-19'));
    // Joined on Tuesday: Monday wasn't theirs, Tuesday was.
    const tuesday = await newMember({ joinedAt: new Date('2026-10-20T17:00:00.000Z') });
    await expect(
      plans.save({
        member: tuesday,
        weekStart: thisWeek,
        days: [rest, rest, rest, train, train, train, train],
      }),
    ).rejects.toThrow(new PlanDayStartedError('2026-10-20'));
    // Monday can rest too: from Tuesday on, the week keeps its two rest days.
    const days: PlanDays = [rest, train, rest, train, train, train, rest];
    expect((await plans.save({ member: tuesday, weekStart: thisWeek, days })).days).toStrictEqual(
      days,
    );
  });

  it('keeps the rest days of this week, even when its plan is carried over', async () => {
    const member = await newMember({ joinedAt: new Date('2026-10-14T17:00:00.000Z') });
    // Saved last week, so this week carries it over.
    now = new Date('2026-10-14T20:00:00.000Z');
    await plans.save({ member, weekStart: lastWeek, days: mine });
    now = new Date('2026-10-21T20:00:00.000Z');
    await expect(
      plans.save({
        member,
        weekStart: thisWeek,
        days: [swim, rest, train, rest, train, rest, train],
      }),
    ).rejects.toThrow(new RestDaysFixedError(2));
    // Swapping Saturday's rest with Thursday's training is fine.
    const swapped: PlanDays = [swim, rest, train, rest, train, train, train];
    await plans.save({ member, weekStart: thisWeek, days: swapped });
    expect(await storedRows(member)).toStrictEqual([
      { week_start: '2026-10-12', payload: { version: 1, days: mine } },
      { week_start: '2026-10-19', payload: { version: 1, days: swapped } },
    ]);
  });

  it('plans next week without touching this one, and keeps past weeks as they were', async () => {
    const member = await newMember();
    await plans.save({ member, weekStart: thisWeek, days: mine });
    const allTraining: PlanDays = [train, train, train, train, train, train, train];
    await plans.save({ member, weekStart: nextWeek, days: allTraining });
    expect((await plans.find({ member, weekStart: thisWeek })).days).toStrictEqual(mine);
    await expect(plans.save({ member, weekStart: lastWeek, days: mine })).rejects.toThrow(
      new WeekOverError('2026-10-12'),
    );
  });

  it('reads today in the member’s own time zone', async () => {
    // 2026-10-26 05:00 UTC is Monday 13:00 in Shanghai but still Sunday night in Los Angeles.
    now = new Date('2026-10-26T05:00:00.000Z');
    try {
      const shanghai = await newMember({ timeZone: 'Asia/Shanghai' });
      const losAngeles = await newMember();
      await expect(
        plans.save({ member: shanghai, weekStart: thisWeek, days: mine }),
      ).rejects.toThrow(new WeekOverError('2026-10-19'));
      // Still Sunday there: the week takes a save (the default as it is, as every day has begun).
      const defaultDays: PlanDays = [train, train, rest, train, train, train, rest];
      await plans.save({ member: losAngeles, weekStart: thisWeek, days: defaultDays });
    } finally {
      now = new Date('2026-10-21T20:00:00.000Z');
    }
  });

  it('needs the member’s time zone first', async () => {
    const member = await newMember();
    calendars.delete(member);
    await expect(plans.save({ member, weekStart: thisWeek, days: mine })).rejects.toThrow(
      new TimeZoneNotSetError(),
    );
    expect(await storedRows(member)).toStrictEqual([]);
  });
});

describe('a week’s 饮食小目标', () => {
  const water = { kind: 'suggested', suggestion: 'water' } as const;
  const own = { kind: 'own', text: '少喝冰美式' } as const;

  it('sets next week’s, keeps them to that week, and logs each change but no repeat', async () => {
    const member = await newMember();
    await plans.saveFuelGoals({ member, weekStart: nextWeek, goals: [water] });
    await plans.saveFuelGoals({ member, weekStart: nextWeek, goals: [water] });
    const saved = await plans.saveFuelGoals({ member, weekStart: nextWeek, goals: [own, water] });
    expect(saved).toMatchObject({ weekStart: nextWeek, fuelGoals: [own, water] });
    expect(await plans.find({ member, weekStart: nextWeek })).toStrictEqual(saved);
    expect(await plans.find({ member, weekStart: week('2026-11-02') })).toMatchObject({
      fuelGoals: [],
    });
    const { rows } = await sql<{ week_start: string; payload: unknown }>`
      select week_start::text, payload from fuel_goal_events where member_id = ${member} order by id
    `.execute(db);
    expect(rows).toStrictEqual([
      { week_start: '2026-10-26', payload: { version: 1, goals: [water] } },
      { week_start: '2026-10-26', payload: { version: 1, goals: [own, water] } },
    ]);
  });

  it('refuses this week’s and past weeks’, and needs the member’s time zone', async () => {
    const member = await newMember();
    await expect(
      plans.saveFuelGoals({ member, weekStart: thisWeek, goals: [water] }),
    ).rejects.toThrow(new WeekStartedError('2026-10-19'));
    await expect(
      plans.saveFuelGoals({ member, weekStart: lastWeek, goals: [water] }),
    ).rejects.toThrow(new WeekStartedError('2026-10-12'));
    calendars.delete(member);
    await expect(
      plans.saveFuelGoals({ member, weekStart: nextWeek, goals: [water] }),
    ).rejects.toThrow(new TimeZoneNotSetError());
  });

  it('gives the Monday of the week the member joined, in their time zone', async () => {
    // Monday 2026-10-19 01:00 in Los Angeles is still Sunday there, before the 3am turn.
    const member = await newMember({ joinedAt: new Date('2026-10-19T08:00:00.000Z') });
    expect(await plans.find({ member, weekStart: thisWeek })).toMatchObject({
      firstWeek: '2026-10-12',
    });
    calendars.delete(member);
    expect(await plans.find({ member, weekStart: thisWeek })).toMatchObject({
      firstWeek: undefined,
    });
  });
});
