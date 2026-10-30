import { randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import {
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import { unusedWeeklyAwards, unusedWeekSummaryWords } from '../test-kit/weekly-awards.js';

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const members = createMembers({ store: createPostgresProfileStore(db) });
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  accounts: createSupabaseAccounts({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  }),
  revokeAppleSignIn: undefined,
  catalog: catalogOn(db),
  publicRoutes: unlimitedPublicRoutes,
  photos,
  checkIns: createCheckIns({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresCheckInStore(db),
    membership: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent: () => Promise.resolve(true),
    }),
    reactions: createPostgresReactionStore(db),
    plans: createPostgresWeeklyPlanStore(db),
    photos,
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  weeklyPlans: createWeeklyPlans({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  members,
  squads: createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: () => Promise.resolve(true),
  }),
  push: pushOn(db),
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  aiConsent: aiConsentOn(db),
  nudges: nudgesOn(db),
  weeklyAwards: unusedWeeklyAwards,
  weekSummaryWords: unusedWeekSummaryWords,
  log: createLog(() => undefined),
  jobs: noJobs,
  admin: adminOn(),
});

/** A squad with these members. Squads have no routes yet, so the test writes it directly. */
async function squadOf(...joined: readonly { readonly userId: string }[]) {
  const id = randomUUID();
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${id})`.execute(
    db,
  );
  for (const [index, member] of joined.entries()) {
    const joinedAt = new Date(Date.UTC(2026, 9, 1, 0, index)).toISOString();
    await sql`insert into public.squad_members (squad_id, member_id, joined_at)
      values (${id}, ${member.userId}, ${joinedAt})`.execute(db);
  }
  return id;
}

async function call(
  method: string,
  {
    path,
    token,
    body,
  }: { readonly path: string; readonly token?: string; readonly body?: unknown },
) {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  const response = await app.request(path, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const json: unknown = await response.json();
  return { status: response.status, body: json };
}

const HOUR = 3_600_000;
/** Any ISO 8601 time, as the API writes them. */
const isoTime: unknown = expect.stringMatching(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
/** Today on a clock `offset` hours ahead of UTC: the date 3 hours earlier (the 3am grace). */
const today = (offset = 0) => new Date(Date.now() + (offset - 3) * HOUR).toISOString().slice(0, 10);

async function member(
  timeZone = 'UTC',
  {
    catchphrase = null,
    character,
  }: { readonly catchphrase?: string | null; readonly character?: unknown } = {},
) {
  const signedUp = await signUp();
  const saved = await call('PUT', {
    path: '/me/profile',
    token: signedUp.token,
    body: { version: 1, timeZone, catchphrase, character },
  });
  expect(saved.status).toBe(200);
  return signedUp;
}

/** Moves the members' join day weeks back, once their plans are saved, so this week counts from Monday. */
async function joinedWeeksAgo(...members: readonly { readonly userId: string }[]) {
  for (const { userId } of members) {
    await sql`update profiles set created_at = now() - interval '30 days' where member_id = ${userId}`.execute(
      db,
    );
  }
}

/** The Monday of the week `day` is in. */
function mondayOf(day: string) {
  const date = new Date(`${day}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() - ((date.getUTCDay() + 6) % 7));
  return date.toISOString().slice(0, 10);
}

/** Saves the member's plan for their week from `day`: every day `kind`. */
async function planAll(token: string, { day, kind }: { day: string; kind: 'train' | 'rest' }) {
  const saved = await call('PUT', {
    path: `/me/weekly-plans/${mondayOf(day)}`,
    token,
    body: { version: 1, days: Array.from({ length: 7 }, () => ({ kind })) },
  });
  expect(saved.status).toBe(200);
}

async function checkIn(
  token: string,
  { squad, ...entry }: { readonly squad: string } & Record<string, unknown>,
) {
  const createdAt = new Date(Date.now() - 60_000).toISOString();
  const body = { version: 1, day: today(), createdAt, audience: [squad], ...entry };
  const saved = await call('PUT', { path: `/check-ins/${randomUUID()}`, token, body });
  expect(saved.status).toBe(201);
}

describe('GET /squads/{squadId}/today', () => {
  it('gives each member’s today and the week’s counts', async () => {
    const [me, friend] = [await member(), await member()];
    // 25 hours apart, so their todays are never the same date: each must be read in their own zone.
    const [east, west] = [await member('Pacific/Kiritimati'), await member('Pacific/Pago_Pago')];
    const squad = await squadOf(me, friend, east, west);
    // East trains every day this week and West rests every day; me and friend keep the default.
    await planAll(east.token, { day: today(14), kind: 'train' });
    await planAll(west.token, { day: today(-11), kind: 'rest' });
    await joinedWeeksAgo(me, friend, east, west);
    await checkIn(me.token, { squad, kind: 'disclaimer', disclaimer: { text: '加班' } });
    await checkIn(me.token, { squad, kind: 'trained', training: { sport: 'run' } });
    await checkIn(friend.token, { squad, kind: 'healthyMeal', meal: {} });

    const { status, body } = await call('GET', {
      path: `/squads/${squad}/today`,
      token: friend.token,
    });
    expect(status).toBe(200);
    expect(body).toMatchObject({
      version: 1,
      squad,
      // Checked in today by first check-in, then the planned rest, then the rest.
      members: [
        {
          member: me.userId,
          day: today(),
          training: 'trained',
          firstCheckInAt: isoTime,
        },
        {
          member: friend.userId,
          day: today(),
          training: 'notCheckedIn',
          latestMeal: 'healthyMeal',
          firstCheckInAt: isoTime,
        },
        { member: west.userId, day: today(-11), training: 'notCheckedIn', plannedRest: true },
        { member: east.userId, day: today(14), training: 'notCheckedIn', plannedRest: false },
      ],
      today: { trained: 1, disclaimer: 0, everyoneTrained: false },
      me: { week: { trainedDays: 0, plannedDays: 5 }, lifetimeTrainedDays: 0 },
      // Planned: 5 + 5 + 7 + 0.
      squadWeek: { trainedDays: 1, plannedDays: 17 },
    });
    expect(body).not.toHaveProperty('members.0.latestMeal');
    expect(body).not.toHaveProperty('members.2.firstCheckInAt');
  });

  it('shows squadmates each member’s catchphrase, and null for one who hasn’t picked one', async () => {
    const [shouter, quiet] = [await member('UTC', { catchphrase: '冲就完了🔥' }), await member()];
    const squad = await squadOf(shouter, quiet);
    const { status, body } = await call('GET', {
      path: `/squads/${squad}/today`,
      token: quiet.token,
    });
    expect(status).toBe(200);
    expect(body).toMatchObject({
      members: [
        { member: shouter.userId, catchphrase: '冲就完了🔥' },
        { member: quiet.userId, catchphrase: null },
      ],
    });
  });

  it('shows squadmates each member’s nickname and look, and none for one who hasn’t made them', async () => {
    const character = {
      nickname: '小周',
      look: {
        persona: 'showoff',
        variants: { body: 'peach', hair: 'bun' },
        colors: { hair: '#3B2A20' },
      },
    };
    const [made, notYet] = [await member('UTC', { character }), await member()];
    const squad = await squadOf(made, notYet);
    const { status, body } = await call('GET', {
      path: `/squads/${squad}/today`,
      token: notYet.token,
    });
    expect(status).toBe(200);
    expect(body).toMatchObject({
      members: [{ member: made.userId, character }, { member: notYet.userId }],
    });
    expect(body).not.toHaveProperty('members.1.character');
  });

  it('answers only the squad’s members', async () => {
    const [insider, outsider] = [await member(), await member()];
    const squad = await squadOf(insider);
    expect(
      await call('GET', { path: `/squads/${squad}/today`, token: outsider.token }),
    ).toMatchObject({
      status: 403,
      body: { reason: 'SQUAD_NOT_JOINED' },
    });
    expect(await call('GET', { path: `/squads/${squad}/today` })).toMatchObject({ status: 401 });
  });

  it('refuses a squad id that isn’t one', async () => {
    const { token } = await member();
    expect(await call('GET', { path: '/squads/not-a-squad/today', token })).toMatchObject({
      status: 400,
      body: { reason: 'REQUEST_INVALID' },
    });
  });
});
