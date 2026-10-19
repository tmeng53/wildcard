import { randomUUID } from 'node:crypto';

import { createCheckIns, createPostgresCheckInStore } from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { sign } from 'hono/jwt';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { config, signUp } from '../test-kit/local-supabase.js';

async function send(
  path: string,
  { supabaseUrl = config.supabaseUrl, ...init }: RequestInit & { supabaseUrl?: string },
) {
  const db = createDatabase(config.databaseUrl);
  const photos = createSupabasePhotoStorage({ supabaseUrl, secretKey: config.supabaseSecretKey });
  const app = createApp({
    db,
    verifyToken: createSupabaseTokenVerifier({ supabaseUrl }),
    checkIns: createCheckIns({
      store: createPostgresCheckInStore(db),
      photos,
      zones: createMembers({ store: createPostgresProfileStore(db) }),
      clock: () => new Date(),
    }),
    photos,
    members: createMembers({ store: createPostgresProfileStore(db) }),
    log: createLog(() => undefined),
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
    const profile = { version: 1, timeZone: 'America/Los_Angeles' };
    expect(await putProfile(token, profile)).toStrictEqual([200, profile]);
    expect(await getMe({ authorization: `Bearer ${token}` })).toStrictEqual([
      200,
      { version: 1, userId, profile: { timeZone: 'America/Los_Angeles' } },
    ]);
  });

  it('replaces the profile on a later save, and a repeat changes nothing', async () => {
    const { token, userId } = await signUp();
    await putProfile(token, { version: 1, timeZone: 'America/Los_Angeles' });
    const moved = { version: 1, timeZone: 'America/Toronto' };
    expect(await putProfile(token, moved)).toStrictEqual([200, moved]);
    expect(await putProfile(token, moved)).toStrictEqual([200, moved]);
    expect(await getMe({ authorization: `Bearer ${token}` })).toStrictEqual([
      200,
      { version: 1, userId, profile: { timeZone: 'America/Toronto' } },
    ]);
  });

  it('keeps each member’s profile to themselves', async () => {
    const tracy = await signUp();
    const friend = await signUp();
    await putProfile(tracy.token, { version: 1, timeZone: 'America/Los_Angeles' });
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
    const profile = { version: 1, timeZone };
    expect(await putProfile(token, profile)).toStrictEqual([200, profile]);
  });

  it('refuses a zone that doesn’t exist', async () => {
    const { token } = await signUp();
    expect(await putProfile(token, { version: 1, timeZone: 'Mars/Jezero_Crater' })).toStrictEqual([
      400,
      {
        version: 1,
        type: 'about:blank',
        title: 'Bad Request',
        status: 400,
        detail: 'Mars/Jezero_Crater is not a known time zone.',
        reason: 'TIME_ZONE_UNKNOWN',
        errorStatus: 'INVALID_ARGUMENT',
      },
    ]);
  });

  it.each([
    ['an offset instead of a name', { version: 1, timeZone: '-08:00' }],
    ['no version', { timeZone: 'America/Los_Angeles' }],
    ['an unknown field', { version: 1, timeZone: 'America/Los_Angeles', weight: 60 }],
  ])('refuses %s', async (_case, body) => {
    const { token } = await signUp();
    const [status, problemBody] = await putProfile(token, body);
    expect([status, z.object({ reason: z.string() }).parse(problemBody).reason]).toStrictEqual([
      400,
      'REQUEST_INVALID',
    ]);
  });

  it('asks a caller with no token to sign in', async () => {
    expect(
      await send('/me/profile', {
        method: 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ version: 1, timeZone: 'America/Los_Angeles' }),
      }),
    ).toStrictEqual([401, problem('AUTH_TOKEN_MISSING', 'Sign in to do this.')]);
  });
});
