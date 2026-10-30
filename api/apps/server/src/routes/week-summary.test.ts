import { randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresWeekSummaryWords,
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
import { unusedWeeklyAwards } from '../test-kit/weekly-awards.js';

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
  weekSummaryWords: () => createPostgresWeekSummaryWords(db).current(),
  log: createLog(() => undefined),
  admin: adminOn(),
  jobs: noJobs,
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
    language,
  }: {
    readonly path: string;
    readonly token?: string;
    readonly body?: unknown;
    readonly language?: string;
  },
) {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  if (language !== undefined) headers['accept-language'] = language;
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
    // Me plans a week of rest; the 练了 makes today a training day, and completes the week.
    await planAll(me.token, { day: today(), kind: 'rest' });
    await joinedWeeksAgo(me, friend);
    await checkIn(me.token, { squad, kind: 'trained', training: { sport: 'run' } });
    const excuse = await checkIn(friend.token, {
      squad,
      kind: 'disclaimer',
      disclaimer: { text: '加班' },
    });
    const reacted = await call('PUT', {
      path: `/check-ins/${excuse}/reactions/mine`,
      token: me.token,
      body: { version: 1, emoji: '😂' },
    });
    expect(reacted.status).toBe(201);

    const monday = mondayOf(today());
    const { status, body } = await call('GET', { path: summaryOf(squad, monday), token: me.token });
    expect(status).toBe(200);
    expect(body).toMatchObject({
      version: 1,
      language: 'zh-Hans',
      squad,
      week: { from: monday },
      final: false,
      awards: [
        {
          kind: 'planCompleted',
          title: '领奖台',
          symbol: 'checkmark.seal.fill',
          winners: [{ member: me.userId, value: 1, text: '练了 1 天' }],
        },
        {
          kind: 'crown',
          title: '皇冠',
          symbol: 'crown.fill',
          winners: [{ member: me.userId, value: 1, text: '练了 1 天' }],
        },
        {
          kind: 'bestDisclaimer',
          title: '本周最佳请假条',
          symbol: 'text.bubble.fill',
          winners: [{ member: friend.userId, value: 1, text: '1 个回应', checkIn: excuse }],
        },
      ],
      squadTotals: {
        stats: [
          { kind: 'trainedDays', label: '训练天数', value: 1 },
          // Me's 练了 day, and friend's default 5.
          { kind: 'plannedDays', label: '计划天数', value: 6 },
          { kind: 'checkIns', label: '打卡', value: 2 },
          { kind: 'disclaimers', label: '请假条', value: 1 },
          { kind: 'healthyMeals', label: '健康餐', value: 0 },
          { kind: 'cheatMeals', label: '放纵餐', value: 0 },
          { kind: 'reactionsReceived', label: '收到的回应', value: 1 },
        ],
        reactions: [{ emoji: '😂', count: 1 }],
      },
      me: {
        stats: [
          { kind: 'trainedDays', value: 1 },
          { kind: 'plannedDays', value: 1 },
          { kind: 'checkIns', value: 1 },
          { kind: 'disclaimers', value: 0 },
          { kind: 'healthyMeals', value: 0 },
          { kind: 'cheatMeals', value: 0 },
          { kind: 'reactionsReceived', value: 0 },
        ],
        reactions: [{ emoji: '😂', received: 0, given: 1 }],
      },
    });
    expect(body).not.toHaveProperty('awards.0.winners.0.checkIn');

    const english = await call('GET', {
      path: summaryOf(squad, monday),
      token: me.token,
      language: 'en-US,en;q=0.9,zh-Hans;q=0.8',
    });
    expect(english.body).toMatchObject({
      language: 'en',
      awards: [
        { title: 'Podium', winners: [{ text: 'Trained 1 day' }] },
        { title: 'Crown', winners: [{ text: 'Trained 1 day' }] },
        { title: 'Day-off note of the week', winners: [{ text: '1 reaction' }] },
      ],
    });
    expect(english.body).toHaveProperty('squadTotals.stats.0.label', 'Days trained');
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
