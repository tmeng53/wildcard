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
import { sign } from 'hono/jwt';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { adminOn, config, signUp } from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';

async function send(
  path: string,
  { supabaseUrl = config.supabaseUrl, ...init }: RequestInit & { supabaseUrl?: string },
) {
  const db = createDatabase(config.databaseUrl);
  const photos = createSupabasePhotoStorage({ supabaseUrl, secretKey: config.supabaseSecretKey });
  const app = createApp({
    db,
    verifyToken: createSupabaseTokenVerifier({ supabaseUrl }),
    accounts: createSupabaseAccounts({ supabaseUrl, secretKey: config.supabaseSecretKey }),
    revokeAppleSignIn: undefined,
    publicRoutes: unlimitedPublicRoutes,
    checkIns: createCheckIns({
      store: createPostgresCheckInStore(db),
      reactions: createPostgresReactionStore(db),
      plans: createPostgresWeeklyPlanStore(db),
      photos,
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    photos,
    disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
    weeklyPlans: createWeeklyPlans({
      store: createPostgresWeeklyPlanStore(db),
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    members: createMembers({ store: createPostgresProfileStore(db) }),
    push: createPush({ store: createPostgresDeviceStore(db), sender: createOffSender() }),
    squads: createSquads({ store: createPostgresSquadStore(db), inviteCodes: randomInviteCodes }),
    log: createLog(() => undefined),
    admin: adminOn(),
  });
  try {
    const response = await app.request(path, init);
    return [response.status, await response.json()];
  } finally {
    await db.destroy();
  }
}

const getMe = (headers: Record<string, string>, supabaseUrl?: string) =>
  send('/me', { headers, ...(supabaseUrl === undefined ? {} : { supabaseUrl }) });

const putProfile = (token: string, body: unknown) =>
  send('/me/profile', {
    method: 'PUT',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

const problem = (reason: string, detail: string) => ({
  version: 1,
  type: 'about:blank',
  title: 'Unauthorized',
  status: 401,
  detail,
  reason,
  errorStatus: 'UNAUTHENTICATED',
});
const invalid = problem(
  'AUTH_TOKEN_INVALID',
  'The sign-in has expired or is not valid. Sign in again.',
);

describe('GET /me', () => {
  it('says who a member signed in with Supabase Auth is', async () => {
    const { token, userId } = await signUp();
    expect(await getMe({ authorization: `Bearer ${token}` })).toStrictEqual([
      200,
      { version: 1, userId, profile: null },
    ]);
  });

  it('asks a caller with no token to sign in', async () => {
    expect(await getMe({})).toStrictEqual([
      401,
      problem('AUTH_TOKEN_MISSING', 'Sign in to do this.'),
    ]);
  });

  it.each([
    ['not a bearer token', 'Basic dXNlcjpwYXNz'],
    ['not a JWT', 'Bearer not-a-jwt'],
  ])('refuses %s', async (_case, authorization) => {
    expect(await getMe({ authorization })).toStrictEqual([401, invalid]);
  });

  it('refuses a token signed with a shared secret, even one naming our key', async () => {
    // The legacy anon and service keys are HS256: knowing a secret must never sign anyone in.
    const { token } = await signUp();
    const [header] = token.split('.');
    const { kid } = z
      .object({ kid: z.string() })
      .parse(JSON.parse(Buffer.from(header ?? '', 'base64url').toString()));
    const forged = await sign(
      { sub: randomUUID(), role: 'authenticated', aud: 'authenticated', exp: 2_000_000_000 },
      'any shared secret, however long or well kept',
    );
    const [, payload, signature] = forged.split('.');
    const withKid = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT', kid })).toString(
      'base64url',
    );
    expect(
      await getMe({ authorization: `Bearer ${withKid}.${payload ?? ''}.${signature ?? ''}` }),
    ).toStrictEqual([401, invalid]);
  });

  it('refuses a real token with one changed character in its claims', async () => {
    const { token } = await signUp();
    const [header, payload, signature] = token.split('.');
    const claims = z
      .looseObject({ sub: z.string() })
      .parse(JSON.parse(Buffer.from(payload ?? '', 'base64url').toString()));
    const tampered = Buffer.from(JSON.stringify({ ...claims, sub: randomUUID() })).toString(
      'base64url',
    );
    expect(
      await getMe({ authorization: `Bearer ${header ?? ''}.${tampered}.${signature ?? ''}` }),
    ).toStrictEqual([401, invalid]);
  });

  it('answers 503 when Supabase Auth’s keys can’t be fetched', async () => {
    const { token } = await signUp();
    // Nothing listens on port 1.
    expect(await getMe({ authorization: `Bearer ${token}` }, 'http://127.0.0.1:1')).toStrictEqual([
      503,
      {
        version: 1,
        type: 'about:blank',
        title: 'Service Unavailable',
        status: 503,
        detail: 'Sign-in can’t be checked right now. Try again shortly.',
        reason: 'AUTH_KEYS_UNAVAILABLE',
        errorStatus: 'UNAVAILABLE',
      },
    ]);
  });
});

describe('PUT /me/profile', () => {
  it('creates the profile on the first save, and GET /me returns it', async () => {
    const { token, userId } = await signUp();
    const profile = { version: 1, timeZone: 'America/Los_Angeles', catchphrase: null };
    expect(await putProfile(token, profile)).toStrictEqual([200, profile]);
    expect(await getMe({ authorization: `Bearer ${token}` })).toStrictEqual([
      200,
      { version: 1, userId, profile: { timeZone: 'America/Los_Angeles', catchphrase: null } },
    ]);
  });

  it('replaces the profile on a later save, and a repeat changes nothing', async () => {
    const { token, userId } = await signUp();
    await putProfile(token, { version: 1, timeZone: 'America/Los_Angeles', catchphrase: null });
    const moved = { version: 1, timeZone: 'America/Toronto', catchphrase: null };
    expect(await putProfile(token, moved)).toStrictEqual([200, moved]);
    expect(await putProfile(token, moved)).toStrictEqual([200, moved]);
    expect(await getMe({ authorization: `Bearer ${token}` })).toStrictEqual([
      200,
      { version: 1, userId, profile: { timeZone: 'America/Toronto', catchphrase: null } },
    ]);
  });

  it('saves a catchphrase trimmed, counting an emoji as one character, and clears it with null', async () => {
    const { token, userId } = await signUp();
    const zone = 'America/Los_Angeles';
    // 10 characters: 9 Chinese characters and an emoji with a skin tone.
    const shout = '今天也冲冲冲的一天👍🏽';
    expect(
      await putProfile(token, { version: 1, timeZone: zone, catchphrase: `  ${shout}\n` }),
    ).toStrictEqual([200, { version: 1, timeZone: zone, catchphrase: shout }]);
    expect(await getMe({ authorization: `Bearer ${token}` })).toStrictEqual([
      200,
      { version: 1, userId, profile: { timeZone: zone, catchphrase: shout } },
    ]);
    // The body is the whole profile, so leaving the catchphrase out clears it too.
    await putProfile(token, { version: 1, timeZone: zone, catchphrase: shout });
    expect(await putProfile(token, { version: 1, timeZone: zone })).toStrictEqual([
      200,
      { version: 1, timeZone: zone, catchphrase: null },
    ]);
    await putProfile(token, { version: 1, timeZone: zone, catchphrase: shout });
    expect(
      await putProfile(token, { version: 1, timeZone: zone, catchphrase: null }),
    ).toStrictEqual([200, { version: 1, timeZone: zone, catchphrase: null }]);
    expect(await getMe({ authorization: `Bearer ${token}` })).toStrictEqual([
      200,
      { version: 1, userId, profile: { timeZone: zone, catchphrase: null } },
    ]);
  });

  it.each([
    ['over 10 characters', '今天也是冲冲冲的一天!'],
    ['on two lines', '冲\n冲'],
    ['that is blank', ' \u3000 '],
    ['that is empty', ''],
    ['with a link', '看abc.com'],
    ['with a link written with a full-width dot', 'abc。com'],
    ['with a web address', 'https://a'],
  ])('refuses a catchphrase %s', async (_case, catchphrase) => {
    const { token } = await signUp();
    const [status, problemBody] = await putProfile(token, {
      version: 1,
      timeZone: 'America/Los_Angeles',
      catchphrase,
    });
    expect([status, z.object({ reason: z.string() }).parse(problemBody).reason]).toStrictEqual([
      400,
      'REQUEST_INVALID',
    ]);
  });

  it('keeps each member’s profile to themselves', async () => {
    const tracy = await signUp();
    const friend = await signUp();
    await putProfile(tracy.token, {
      version: 1,
      timeZone: 'America/Los_Angeles',
      catchphrase: null,
    });
    expect(await getMe({ authorization: `Bearer ${friend.token}` })).toStrictEqual([
      200,
      { version: 1, userId: friend.userId, profile: null },
    ]);
  });

  it.each([
    ['by its old name', 'Asia/Calcutta'],
    ['with no area', 'GMT'],
    ['with digits in its first part', 'EST5EDT'],
  ])('accepts a zone iOS may report %s', async (_case, timeZone) => {
    const { token } = await signUp();
    const profile = { version: 1, timeZone, catchphrase: null };
    expect(await putProfile(token, profile)).toStrictEqual([200, profile]);
  });

  it.each([
    ['that doesn’t exist', 'Mars/Jezero_Crater'],
    // Postgres knows these, but Node can't read days in them.
    ['only Postgres knows', 'posix/America/Los_Angeles'],
    ['that is a placeholder', 'Factory'],
  ])('refuses a zone %s', async (...[, timeZone]) => {
    const { token } = await signUp();
    expect(await putProfile(token, { version: 1, timeZone, catchphrase: null })).toStrictEqual([
      400,
      {
        version: 1,
        type: 'about:blank',
        title: 'Bad Request',
        status: 400,
        detail: `${timeZone} is not a known time zone.`,
        reason: 'TIME_ZONE_UNKNOWN',
        errorStatus: 'INVALID_ARGUMENT',
      },
    ]);
  });

  it.each([
    ['an offset instead of a name', { version: 1, timeZone: '-08:00', catchphrase: null }],
    ['no version', { timeZone: 'America/Los_Angeles', catchphrase: null }],
    [
      'an unknown field',
      { version: 1, timeZone: 'America/Los_Angeles', catchphrase: null, weight: 60 },
    ],
  ])('refuses %s', async (_case, body) => {
    const { token } = await signUp();
    const [status, problemBody] = await putProfile(token, body);
    expect([status, z.object({ reason: z.string() }).parse(problemBody).reason]).toStrictEqual([
      400,
      'REQUEST_INVALID',
    ]);
  });

  it("refuses a body that isn't JSON", async () => {
    const { token } = await signUp();
    const [status, problemBody] = await send('/me/profile', {
      method: 'PUT',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: 'nope',
    });
    expect([status, z.object({ reason: z.string() }).parse(problemBody).reason]).toStrictEqual([
      400,
      'REQUEST_INVALID',
    ]);
  });

  it("refuses a body that isn't sent as JSON", async () => {
    const { token } = await signUp();
    expect(
      await send('/me/profile', {
        method: 'PUT',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'text/plain' },
        body: JSON.stringify({ version: 1, timeZone: 'America/Los_Angeles', catchphrase: null }),
      }),
    ).toStrictEqual([
      415,
      {
        version: 1,
        type: 'about:blank',
        title: 'Unsupported Media Type',
        status: 415,
        detail: 'Send the body as application/json.',
        reason: 'MEDIA_TYPE_UNSUPPORTED',
        errorStatus: 'INVALID_ARGUMENT',
      },
    ]);
  });

  it('asks a caller with no token to sign in', async () => {
    expect(
      await send('/me/profile', {
        method: 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ version: 1, timeZone: 'America/Los_Angeles', catchphrase: null }),
      }),
    ).toStrictEqual([401, problem('AUTH_TOKEN_MISSING', 'Sign in to do this.')]);
  });
});
