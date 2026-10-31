import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { createPostgresSportStore, createSports, type SportTables } from '@wildcard/sports';
import { z } from 'zod';

import type { CheckInTables } from '../adapters/postgres-check-in-store.js';
import { createPostgresWeeklyPlanStore } from '../adapters/postgres-weekly-plan-store.js';
import { MemberId } from '../domain/check-in.js';
import { WeekStart, type PlanDays } from '../domain/weekly-plan.js';
import {
  PlanDayStartedError,
  SportNotListedError,
  TimeZoneNotSetError,
  WeekOverError,
} from '../errors.js';
import { createWeeklyPlans } from './weekly-plans.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<CheckInTables & SportTables>({
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
  sports: createSports({ store: createPostgresSportStore(db) }),
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

  it('keeps a week’s own plan to that week; other weeks follow the template', async () => {
    const member = await newMember();
    await plans.saveTemplate({ member, days: mine });
    const tired: PlanDays = [swim, rest, rest, rest, rest, rest, rest];
    await plans.save({ member, weekStart: nextWeek, days: tired });
    expect(await plans.find({ member, weekStart: nextWeek })).toStrictEqual({
      weekStart: '2026-10-26',
      days: tired,
      source: 'saved',
      ...joinedThisWeek,
    });
    expect(await plans.find({ member, weekStart: week('2026-11-09') })).toStrictEqual({
      weekStart: '2026-11-09',
      days: mine,
      source: 'template',
      ...joinedThisWeek,
    });
    expect((await plans.find({ member, weekStart: thisWeek })).source).toBe('template');
  });

  it('keeps each member’s plan to themselves', async () => {
    const tracy = await newMember();
    const friend = await newMember();
    await plans.save({ member: tracy, weekStart: thisWeek, days: mine });
    expect((await plans.find({ member: friend, weekStart: thisWeek })).source).toBe('default');
  });
});

describe('the typical week', () => {
  it('is the default before the member makes one', async () => {
    const member = await newMember();
    expect(await plans.template({ member })).toStrictEqual({
      days: [train, train, rest, train, train, train, rest],
      source: 'default',
    });
  });

  it('made at sign-up is this week’s plan and every later week’s', async () => {
    const member = await newMember();
    expect(await plans.saveTemplate({ member, days: mine })).toStrictEqual({
      days: mine,
      source: 'saved',
    });
    expect(await plans.template({ member })).toStrictEqual({ days: mine, source: 'saved' });
    for (const weekStart of [thisWeek, nextWeek, week('2026-11-16')]) {
      expect(await plans.find({ member, weekStart })).toMatchObject({
        days: mine,
        source: 'template',
      });
    }
    expect(await storedRows(member)).toStrictEqual([]);
  });

  it('changed later applies from next week, so this week and past weeks keep theirs', async () => {
    const member = await newMember({ joinedAt: new Date('2026-10-07T17:00:00.000Z') });
    now = new Date('2026-10-07T20:00:00.000Z');
    await plans.saveTemplate({ member, days: mine });
    now = new Date('2026-10-21T20:00:00.000Z');
    const lighter: PlanDays = [swim, rest, rest, train, rest, rest, train];
    await plans.saveTemplate({ member, days: lighter });
    expect(await plans.template({ member })).toStrictEqual({ days: lighter, source: 'saved' });
    expect((await plans.find({ member, weekStart: lastWeek })).days).toStrictEqual(mine);
    expect((await plans.find({ member, weekStart: thisWeek })).days).toStrictEqual(mine);
    expect((await plans.find({ member, weekStart: nextWeek })).days).toStrictEqual(lighter);
    // Changed again the same week: the latest change is the one next week follows.
    await plans.saveTemplate({ member, days: mine });
    expect((await plans.find({ member, weekStart: nextWeek })).days).toStrictEqual(mine);
  });

  it('made first after the join week applies from next week; earlier weeks keep the default', async () => {
    const member = await newMember({ joinedAt: new Date('2026-10-07T17:00:00.000Z') });
    await plans.saveTemplate({ member, days: mine });
    const theDefault = [train, train, rest, train, train, train, rest];
    expect(await plans.find({ member, weekStart: thisWeek })).toMatchObject({
      days: theDefault,
      source: 'default',
    });
    expect(await plans.find({ member, weekStart: nextWeek })).toMatchObject({
      days: mine,
      source: 'template',
    });
  });

  it('changed again on the join day, as going back during sign-up does, is this week’s too', async () => {
    const member = await newMember();
    await plans.saveTemplate({ member, days: mine });
    const lighter: PlanDays = [swim, rest, rest, train, rest, rest, train];
    await plans.saveTemplate({ member, days: lighter });
    expect((await plans.find({ member, weekStart: thisWeek })).days).toStrictEqual(lighter);
  });

  it('made later in the join week waits for next week, so days already over keep their plan', async () => {
    // Joined Monday; today is Wednesday.
    const member = await newMember({ joinedAt: new Date('2026-10-19T17:00:00.000Z') });
    await plans.saveTemplate({ member, days: mine });
    expect((await plans.find({ member, weekStart: thisWeek })).source).toBe('default');
    expect((await plans.find({ member, weekStart: nextWeek })).days).toStrictEqual(mine);
  });

  it('follows the newest change, even over an older one applying from a later week', async () => {
    const member = await newMember({ joinedAt: new Date('2026-10-07T17:00:00.000Z') });
    const store = createPostgresWeeklyPlanStore(db);
    // Such rows come from the migration: a week saved ahead, before templates existed.
    await store.saveTemplate({ member, fromWeek: week('2026-11-09'), days: mine });
    const lighter: PlanDays = [swim, rest, rest, train, rest, rest, train];
    await plans.saveTemplate({ member, days: lighter });
    expect((await plans.find({ member, weekStart: nextWeek })).days).toStrictEqual(lighter);
    expect((await plans.find({ member, weekStart: week('2026-11-16') })).days).toStrictEqual(
      lighter,
    );
  });

  it('logs each change once, with the week it applies from', async () => {
    const member = await newMember();
    await plans.saveTemplate({ member, days: mine });
    await plans.saveTemplate({ member, days: mine });
    const { rows } = await sql<{ from_week: string; payload: unknown }>`
      select from_week::text, payload from plan_templates where member_id = ${member} order by id
    `.execute(db);
    expect(rows).toStrictEqual([{ from_week: '2026-10-19', payload: { version: 1, days: mine } }]);
  });

  it('is refused before a profile, or naming a sport the list doesn’t have', async () => {
    const member = await newMember();
    calendars.delete(member);
    await expect(plans.saveTemplate({ member, days: mine })).rejects.toThrow(TimeZoneNotSetError);
    const other = await newMember();
    await expect(
      plans.saveTemplate({
        member: other,
        days: [{ kind: 'train', sport: 'quidditch' }, ...mine.slice(1)],
      }),
    ).rejects.toThrow(SportNotListedError);
  });

  it('lets the member change any day of this week on the day they join', async () => {
    const member = await newMember();
    await plans.saveTemplate({ member, days: mine });
    const allRest: PlanDays = [rest, rest, rest, rest, rest, rest, rest];
    await plans.save({ member, weekStart: thisWeek, days: allRest });
    expect((await plans.find({ member, weekStart: thisWeek })).days).toStrictEqual(allRest);
  });
});

describe('a planned day’s sport', () => {
  it('is a listed sport or 其他; another id is refused', async () => {
    const member = await newMember();
    const days = (sport: string, customSport?: string): PlanDays => [
      { kind: 'train', sport, ...(customSport === undefined ? {} : { customSport }) },
      ...mine.slice(1),
    ];
    await expect(
      plans.save({ member, weekStart: nextWeek, days: days('quidditch') }),
    ).rejects.toThrow(SportNotListedError);
    await plans.save({ member, weekStart: nextWeek, days: days('custom', '魁地奇') });
    await plans.save({ member, weekStart: nextWeek, days: days('pickleball') });
    expect((await plans.find({ member, weekStart: nextWeek })).days[0]).toStrictEqual({
      kind: 'train',
      sport: 'pickleball',
    });
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
    // Monday can rest too: it was before they joined.
    const days: PlanDays = [rest, train, rest, train, train, train, rest];
    expect((await plans.save({ member: tuesday, weekStart: thisWeek, days })).days).toStrictEqual(
      days,
    );
  });

  it('lets later days of this week rest or train, even when it follows the template', async () => {
    const member = await newMember({ joinedAt: new Date('2026-10-14T17:00:00.000Z') });
    // Made last week, so this week follows it.
    now = new Date('2026-10-14T20:00:00.000Z');
    await plans.saveTemplate({ member, days: mine });
    now = new Date('2026-10-21T20:00:00.000Z');
    // Thursday becomes a training day and Saturday a rest day: three rest days now.
    const swapped: PlanDays = [swim, rest, train, train, train, rest, rest];
    await plans.save({ member, weekStart: thisWeek, days: swapped });
    expect(await storedRows(member)).toStrictEqual([
      { week_start: '2026-10-19', payload: { version: 1, days: swapped } },
    ]);
  });

  it('lets a rest today become a training day, with one rest day fewer', async () => {
    const member = await newMember({ joinedAt: new Date('2026-10-14T17:00:00.000Z') });
    // Rest today, Wednesday, and Sunday.
    const resting: PlanDays = [swim, train, rest, train, train, train, rest];
    now = new Date('2026-10-14T20:00:00.000Z');
    await plans.saveTemplate({ member, days: resting });
    now = new Date('2026-10-21T20:00:00.000Z');
    const trained: PlanDays = [swim, train, swim, train, train, train, rest];
    expect((await plans.save({ member, weekStart: thisWeek, days: trained })).days).toStrictEqual(
      trained,
    );
    // Once today trains, it stays a training day.
    await expect(plans.save({ member, weekStart: thisWeek, days: resting })).rejects.toThrow(
      new PlanDayStartedError('2026-10-21'),
    );
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

  it('clears a week’s goals, and logs nothing for clearing a week that had none', async () => {
    const member = await newMember();
    await plans.saveFuelGoals({ member, weekStart: week('2026-11-02'), goals: [] });
    await plans.saveFuelGoals({ member, weekStart: nextWeek, goals: [water] });
    const cleared = await plans.saveFuelGoals({ member, weekStart: nextWeek, goals: [] });
    expect(cleared).toMatchObject({ fuelGoals: [] });
    expect(await plans.find({ member, weekStart: nextWeek })).toStrictEqual(cleared);
    const { rows } = await sql<{ week_start: string; payload: unknown }>`
      select week_start::text, payload from fuel_goal_events where member_id = ${member} order by id
    `.execute(db);
    expect(rows).toStrictEqual([
      { week_start: '2026-10-26', payload: { version: 1, goals: [water] } },
      { week_start: '2026-10-26', payload: { version: 1, goals: [] } },
    ]);
  });

  it('takes this week’s, refuses past weeks’, and needs the member’s time zone', async () => {
    const member = await newMember();
    expect(
      await plans.saveFuelGoals({ member, weekStart: thisWeek, goals: [water] }),
    ).toMatchObject({ fuelGoals: [water] });
    await expect(
      plans.saveFuelGoals({ member, weekStart: lastWeek, goals: [water] }),
    ).rejects.toThrow(new WeekOverError('2026-10-12'));
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
