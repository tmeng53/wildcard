import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
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
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import { unusedWeekSummaryWords, unusedWeeklyAwards } from '../test-kit/weekly-awards.js';

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
  weeklyAwards: unusedWeeklyAwards,
  weekSummaryWords: unusedWeekSummaryWords,
  log: createLog(() => undefined),
  jobs: noJobs,
  admin: adminOn(),
});

async function call(
  method: string,
  { path, token, body }: { path: string; token?: string; body?: unknown },
) {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  const response = await app.request(path, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return [response.status, await response.json()];
}

/** A member signed up through local Supabase Auth, with a profile unless asked not to. */
async function member({ profile = true } = {}) {
  const signedUp = await signUp();
  if (profile) {
    await call('PUT', {
      path: '/me/profile',
      token: signedUp.token,
      body: { version: 1, timeZone: 'UTC' },
    });
  }
  return signedUp;
}

const DAY = 86_400_000;
/**
 * The Monday `weeks` weeks from this one. The tests stay two weeks clear of today, so the hour
 * they run at never matters.
 */
function monday(weeks: number) {
  const today = new Date();
  const sinceMonday = (today.getUTCDay() + 6) % 7;
  return new Date(today.getTime() + (7 * weeks - sinceMonday) * DAY).toISOString().slice(0, 10);
}

/** This week's Monday on a UTC clock where a day lasts until 3am: the week a new member joined. */
function joinedWeek() {
  const today = new Date(Date.now() - 3 * 3_600_000);
  const sinceMonday = (today.getUTCDay() + 6) % 7;
  return new Date(today.getTime() - sinceMonday * DAY).toISOString().slice(0, 10);
}

/** The Monday `weeks` weeks after the one a new member is in now, on that same clock. */
const memberWeek = (weeks: number) =>
  new Date(Date.parse(joinedWeek()) + 7 * weeks * DAY).toISOString().slice(0, 10);

const train = { kind: 'train' } as const;
const rest = { kind: 'rest' } as const;
const days = [{ kind: 'train', sport: 'tennis' }, rest, train, train, train, rest, train];

const problem = (reason: string, errorStatus: string): unknown =>
  expect.objectContaining({ version: 1, reason, errorStatus });

describe('/me/weekly-plans/{weekStart}', () => {
  it('saves a plan, reads it back, and carries it into later weeks', async () => {
    const { token, userId } = await member();
    const weekStart = monday(2);
    const saved = {
      version: 1,
      member: userId,
      weekStart,
      days,
      source: 'saved',
      fuelGoals: [],
      firstWeek: joinedWeek(),
    };
    expect(
      await call('PUT', {
        path: `/me/weekly-plans/${weekStart}`,
        token,
        body: { version: 1, days },
      }),
    ).toStrictEqual([200, saved]);
    expect(await call('GET', { path: `/me/weekly-plans/${weekStart}`, token })).toStrictEqual([
      200,
      saved,
    ]);
    expect(await call('GET', { path: `/me/weekly-plans/${monday(3)}`, token })).toStrictEqual([
      200,
      { ...saved, weekStart: monday(3), source: 'carriedOver' },
    ]);
  });

  it('gives a member who hasn’t planned the default week', async () => {
    const { token, userId } = await member();
    expect(await call('GET', { path: `/me/weekly-plans/${monday(0)}`, token })).toStrictEqual([
      200,
      {
        version: 1,
        member: userId,
        weekStart: monday(0),
        days: [train, train, rest, train, train, train, rest],
        source: 'default',
        fuelGoals: [],
        firstWeek: joinedWeek(),
      },
    ]);
  });

  it('leaves out the first week before the member saves a profile', async () => {
    const { token } = await member({ profile: false });
    const [, body] = await call('GET', { path: `/me/weekly-plans/${monday(0)}`, token });
    expect(body).not.toHaveProperty('firstWeek');
  });

  it('keeps past weeks as they were', async () => {
    const { token } = await member();
    expect(
      await call('PUT', {
        path: `/me/weekly-plans/${monday(-2)}`,
        token,
        body: { version: 1, days },
      }),
    ).toStrictEqual([400, problem('WEEK_OVER', 'FAILED_PRECONDITION')]);
  });

  it('needs the member’s profile before saving', async () => {
    const { token } = await member({ profile: false });
    expect(
      await call('PUT', {
        path: `/me/weekly-plans/${monday(2)}`,
        token,
        body: { version: 1, days },
      }),
    ).toStrictEqual([400, problem('TIME_ZONE_NOT_SET', 'FAILED_PRECONDITION')]);
  });

  it('sets next week’s 饮食小目标, only for that week, and refuses this week’s', async () => {
    const { token, userId } = await member();
    const goals = [
      { kind: 'suggested', suggestion: 'water' },
      { kind: 'own', text: '少喝冰美式' },
    ];
    const next = memberWeek(1);
    const set = await call('PUT', {
      path: `/me/weekly-plans/${next}/fuel-goals`,
      token,
      body: { version: 1, goals: [goals[0], { kind: 'own', text: ' 少喝冰美式\n' }] },
    });
    expect(set).toStrictEqual([
      200,
      {
        version: 1,
        member: userId,
        weekStart: next,
        days: [train, train, rest, train, train, train, rest],
        source: 'default',
        fuelGoals: goals,
        firstWeek: joinedWeek(),
      },
    ]);
    expect(await call('GET', { path: `/me/weekly-plans/${next}`, token })).toStrictEqual(set);
    // Goals don't carry over.
    const [, later] = await call('GET', { path: `/me/weekly-plans/${memberWeek(2)}`, token });
    expect(later).toMatchObject({ fuelGoals: [] });
    expect(
      await call('PUT', {
        path: `/me/weekly-plans/${memberWeek(0)}/fuel-goals`,
        token,
        body: { version: 1, goals },
      }),
    ).toStrictEqual([400, problem('WEEK_STARTED', 'FAILED_PRECONDITION')]);
    expect(
      await call('PUT', {
        path: `/me/weekly-plans/${memberWeek(5)}/fuel-goals`,
        token,
        body: { version: 1, goals },
      }),
    ).toStrictEqual([400, problem('WEEK_TOO_FAR_AHEAD', 'INVALID_ARGUMENT')]);
  });

  it.each([
    ['four goals', ['water', 'veggies', 'breakfast', 'earlyDinner']],
    ['the same goal twice', ['water', 'water']],
    ['a suggestion the app doesn’t have', ['protein']],
  ])('refuses %s', async (...[, suggestions]) => {
    const { token } = await member();
    const goals = suggestions.map((suggestion) => ({ kind: 'suggested', suggestion }));
    expect(
      await call('PUT', {
        path: `/me/weekly-plans/${memberWeek(1)}/fuel-goals`,
        token,
        body: { version: 1, goals },
      }),
    ).toStrictEqual([400, problem('REQUEST_INVALID', 'INVALID_ARGUMENT')]);
  });

  it.each([
    ['9 characters', '一二三四五六七八九'],
    ['two lines', '多喝水\n早睡'],
    ['nothing but spaces', '   '],
  ])('refuses a goal of %s', async (...[, text]) => {
    const { token } = await member();
    expect(
      await call('PUT', {
        path: `/me/weekly-plans/${memberWeek(1)}/fuel-goals`,
        token,
        body: { version: 1, goals: [{ kind: 'own', text }] },
      }),
    ).toStrictEqual([400, problem('REQUEST_INVALID', 'INVALID_ARGUMENT')]);
  });

  it.each([
    ['a week that doesn’t start on Monday', 'GET', 1, undefined],
    ['six days', 'PUT', 0, { version: 1, days: days.slice(0, 6) }],
    [
      'a rest day with a sport',
      'PUT',
      0,
      { version: 1, days: [{ kind: 'rest', sport: 'run' }, ...days.slice(1)] },
    ],
    ['another version', 'PUT', 0, { version: 2, days }],
  ])('refuses %s', async (...[, method, offset, body]) => {
    const { token } = await member();
    const weekStart = new Date(Date.parse(monday(2)) + offset * DAY).toISOString().slice(0, 10);
    expect(
      await call(method, { path: `/me/weekly-plans/${weekStart}`, token, body }),
    ).toStrictEqual([400, problem('REQUEST_INVALID', 'INVALID_ARGUMENT')]);
  });

  it('asks a caller with no token to sign in', async () => {
    expect(await call('GET', { path: `/me/weekly-plans/${monday(0)}` })).toStrictEqual([
      401,
      problem('AUTH_TOKEN_MISSING', 'UNAUTHENTICATED'),
    ]);
  });
});
