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

const plans = createPostgresWeeklyPlanStore(db);
// Tuesday 2026-11-10, 3am UTC: still Monday 11-09, 10pm, in New York.
const now = new Date('2026-11-10T03:00:00.000Z');
const NEW_YORK = 'America/New_York';
const checkIns = createCheckIns({
  sports: createSports({ store: createPostgresSportStore(db) }),
  store: createPostgresCheckInStore(db),
  membership: createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: () => Promise.resolve(true),
  }),
  reactions: createPostgresReactionStore(db),
  comments: createPostgresCommentStore(db),
  plans,
  photos: { exists: () => Promise.reject(new Error('unused')), delete: () => Promise.resolve() },
  calendarOf: () =>
    Promise.resolve({ timeZone: NEW_YORK, joinedAt: new Date('2026-09-01T00:00:00.000Z') }),
  clock: () => now,
});

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

async function newSquad(member: MemberId) {
  const id = SquadId.parse(randomUUID());
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${id})`.execute(
    db,
  );
  await sql`insert into public.squad_members (squad_id, member_id, joined_at)
    values (${id}, ${member}, '2026-09-01T00:00:00.000Z')`.execute(db);
  return id;
}

/** A check-in written straight to the table, so any day can be used; shared to `audience`. */
async function checkedIn(
  member: MemberId,
  {
    kind,
    day,
    audience = [],
  }: {
    readonly kind: CheckInRecord['kind'];
    readonly day: string;
    readonly audience?: readonly SquadId[];
  },
) {
  const id = randomUUID();
  const payload = kind === 'trained' ? { version: 1, sport: 'run' } : { version: 1 };
  await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
    values (${id}, ${member}, ${day}, ${`${day}T18:00:00.000Z`}, ${kind}, ${JSON.stringify(payload)})`.execute(
    db,
  );
  for (const [index, squad] of audience.entries()) {
    await sql`insert into public.check_in_squads (check_in_id, squad_id, position)
      values (${id}, ${squad}, ${index + 1})`.execute(db);
  }
}

/** The days from `from` to `to`, both in. */
function daysFrom(from: string, to: string): string[] {
  const days: string[] = [];
  for (let day = Date.parse(from); day <= Date.parse(to); day += 86_400_000) {
    days.push(new Date(day).toISOString().slice(0, 10));
  }
  return days;
}

const train: PlanDay = { kind: 'train' };
const rest: PlanDay = { kind: 'rest' };

describe('currentStreaks', () => {
  it('bridges planned rest days however many weeks back the run goes', async () => {
    const member = await newMember();
    // Every week trains Monday to Saturday and rests on Sunday, back to 2026-09-28.
    for (const monday of daysFrom('2026-09-28', '2026-11-09').filter((_, at) => at % 7 === 0)) {
      await plans.save({
        member,
        weekStart: WeekStart.parse(monday),
        days: [train, train, train, train, train, train, rest],
      });
    }
    // Trained every day but the Sundays from 2026-10-01 to Monday 11-09 (today in New York);
    // 09-30 has none and isn't a rest day, so the run starts the day after.
    for (const day of daysFrom('2026-10-01', '2026-11-09')) {
      if (new Date(day).getUTCDay() !== 0) await checkedIn(member, { kind: 'trained', day });
    }
    await checkedIn(member, { kind: 'trained', day: '2026-09-29' });

    expect(await checkIns.currentStreaks({ member })).toStrictEqual({
      training: { days: 34, from: '2026-10-01', to: '2026-11-09' },
    });
  });

  it('runs through a 坦白放纵餐 without counting it, keeps going while today has none, and only shared posts for a squad', async () => {
    const member = await newMember();
    const squad = await newSquad(member);
    await checkedIn(member, { kind: 'healthyMeal', day: '2026-11-06', audience: [squad] });
    // A 坦白放纵餐 bridges the run like a 请假条: no break, no day added.
    await checkedIn(member, { kind: 'cheatMeal', day: '2026-11-07', audience: [squad] });
    // 仅自己可见: only the member's own view counts it.
    await checkedIn(member, { kind: 'healthyMeal', day: '2026-11-08' });
    // Today (11-09 in New York) has none yet: the run still stands.
    expect(await checkIns.currentStreaks({ member })).toStrictEqual({
      meals: { days: 2, from: '2026-11-06', to: '2026-11-08' },
    });
    // As squadmates see it, 11-08 had nothing, so the run broke.
    expect(await checkIns.currentStreaks({ member, squad })).toStrictEqual({});
  });

  it('counts no meal streak from 坦白放纵餐 alone', async () => {
    const member = await newMember();
    await checkedIn(member, { kind: 'cheatMeal', day: '2026-11-07' });
    await checkedIn(member, { kind: 'cheatMeal', day: '2026-11-08' });
    expect(await checkIns.currentStreaks({ member })).toStrictEqual({});
  });

  it('runs both streaks through a 请假条 day without counting it', async () => {
    const member = await newMember();
    await checkedIn(member, { kind: 'trained', day: '2026-11-06' });
    await checkedIn(member, { kind: 'healthyMeal', day: '2026-11-06' });
    await checkedIn(member, { kind: 'disclaimer', day: '2026-11-07' });
    await checkedIn(member, { kind: 'trained', day: '2026-11-08' });
    await checkedIn(member, { kind: 'healthyMeal', day: '2026-11-08' });
    // Today, 11-09: a 请假条 keeps both going and adds nothing.
    await checkedIn(member, { kind: 'disclaimer', day: '2026-11-09' });
    expect(await checkIns.currentStreaks({ member })).toStrictEqual({
      training: { days: 2, from: '2026-11-06', to: '2026-11-08' },
      meals: { days: 2, from: '2026-11-06', to: '2026-11-08' },
    });
  });
});
