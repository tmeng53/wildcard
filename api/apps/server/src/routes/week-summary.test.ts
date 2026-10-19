import { randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createOffSender, createPostgresDeviceStore, createPush } from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import { adminOn, config, signUp } from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';

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
  publicRoutes: unlimitedPublicRoutes,
  photos,
  checkIns: createCheckIns({
    store: createPostgresCheckInStore(db),
    reactions: createPostgresReactionStore(db),
    plans: createPostgresWeeklyPlanStore(db),
    photos,
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  weeklyPlans: createWeeklyPlans({
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  members,
  squads: createSquads({ store: createPostgresSquadStore(db), inviteCodes: randomInviteCodes }),
  push: createPush({ store: createPostgresDeviceStore(db), sender: createOffSender() }),
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  log: createLog(() => undefined),
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
/** Today on a clock `offset` hours ahead of UTC: the date 3 hours earlier (the 3am grace). */
const today = (offset = 0) => new Date(Date.now() + (offset - 3) * HOUR).toISOString().slice(0, 10);

async function member(timeZone = 'UTC') {
  const signedUp = await signUp();
  const saved = await call('PUT', {
    path: '/me/profile',
    token: signedUp.token,
    body: { version: 1, timeZone },
  });
  expect(saved.status).toBe(200);
  return signedUp;
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

/** A check-in the member posts now to `squad`; its id. */
async function checkIn(
  token: string,
  { squad, ...entry }: { readonly squad: string } & Record<string, unknown>,
) {
  const id = randomUUID();
  const createdAt = new Date(Date.now() - 60_000).toISOString();
  const body = { version: 1, day: today(), createdAt, audience: [squad], ...entry };
  const saved = await call('PUT', { path: `/check-ins/${id}`, token, body });
  expect(saved.status).toBe(201);
  return id;
}

const summaryOf = (squad: string, monday: string) => `/squads/${squad}/weeks/${monday}/summary`;

describe('GET /squads/{squadId}/weeks/{weekStart}/summary', () => {
  it('gives the week’s awards and counts', async () => {
    const [me, friend] = [await member(), await member()];
    const squad = await squadOf(me, friend);
    // Me plans a week of rest, so one 练了 completes it.
    await planAll(me.token, { day: today(), kind: 'rest' });
    await checkIn(me.token, { squad, kind: 'trained', training: { sport: 'run' } });
    const excuse = await checkIn(friend.token, {
      squad,
      kind: 'disclaimer',
      disclaimer: { text: '加班' },
    });
    const reacted = await call('PUT', {
      path: `/check-ins/${excuse}/reactions/mine`,
      token: me.token,
      body: { version: 1, kind: 'lol' },
    });
    expect(reacted.status).toBe(201);

    const monday = mondayOf(today());
    const { status, body } = await call('GET', { path: summaryOf(squad, monday), token: me.token });
    expect(status).toBe(200);
    expect(body).toMatchObject({
      version: 1,
      squad,
      week: { from: monday },
      final: false,
      awards: [
        { kind: 'planCompleted', winners: [{ member: me.userId, value: 1 }] },
        { kind: 'crown', winners: [{ member: me.userId, value: 1 }] },
        {
          kind: 'bestDisclaimer',
          winners: [{ member: friend.userId, value: 1, checkIn: excuse }],
        },
      ],
      squadTotals: {
        stats: [
          { kind: 'trainedDays', value: 1 },
          // Me plans none; friend keeps the default 5.
          { kind: 'plannedDays', value: 5 },
          { kind: 'checkIns', value: 2 },
          { kind: 'disclaimers', value: 1 },
          { kind: 'healthyMeals', value: 0 },
          { kind: 'cheatMeals', value: 0 },
          { kind: 'reactionsReceived', value: 1 },
        ],
        reactions: [
          { kind: 'cheer', count: 0 },
          { kind: 'highlight', count: 0 },
          { kind: 'lol', count: 1 },
        ],
      },
      me: {
        stats: [
          { kind: 'trainedDays', value: 1 },
          { kind: 'plannedDays', value: 0 },
          { kind: 'checkIns', value: 1 },
          { kind: 'disclaimers', value: 0 },
          { kind: 'healthyMeals', value: 0 },
          { kind: 'cheatMeals', value: 0 },
          { kind: 'reactionsReceived', value: 0 },
        ],
        reactions: [
          { kind: 'cheer', received: 0, given: 0 },
          { kind: 'highlight', received: 0, given: 0 },
          { kind: 'lol', received: 0, given: 1 },
        ],
      },
    });
    expect(body).not.toHaveProperty('awards.0.winners.0.checkIn');
  });

  it('refuses a day that isn’t a Monday, a week not started, and non-members', async () => {
    const [insider, outsider] = [await member(), await member()];
    const squad = await squadOf(insider);
    const monday = mondayOf(today());
    const nextMonday = new Date(Date.parse(monday) + 7 * 24 * HOUR).toISOString().slice(0, 10);
    const tuesday = new Date(Date.parse(monday) + 24 * HOUR).toISOString().slice(0, 10);
    expect(
      await call('GET', { path: summaryOf(squad, nextMonday), token: insider.token }),
    ).toMatchObject({ status: 400, body: { reason: 'WEEK_NOT_STARTED' } });
    expect(
      await call('GET', { path: summaryOf(squad, tuesday), token: insider.token }),
    ).toMatchObject({ status: 400, body: { reason: 'REQUEST_INVALID' } });
    expect(
      await call('GET', { path: summaryOf(squad, monday), token: outsider.token }),
    ).toMatchObject({ status: 403, body: { reason: 'SQUAD_NOT_JOINED' } });
    expect(await call('GET', { path: summaryOf(squad, monday) })).toMatchObject({ status: 401 });
  });
});
