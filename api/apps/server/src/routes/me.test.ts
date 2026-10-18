import { randomUUID } from 'node:crypto';

import { createCheckIns, createPostgresCheckInStore } from '@wildcard/check-ins';
import { sign } from 'hono/jwt';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createApp } from '../app.js';
import { readConfig } from '../config.js';
import { createLog } from '../log.js';

// Local Supabase, as `supabase status -o env` prints it (scripts/verify.sh passes it in).
const config = readConfig(process.env);
const publishableKey = z.string().min(1).parse(process.env.SUPABASE_PUBLISHABLE_KEY);

const SignUp = z.object({ access_token: z.string(), user: z.object({ id: z.uuid() }) });

/** Signs a new member up through local Supabase Auth and returns their real access token. */
async function signUp() {
  const response = await fetch(`${config.supabaseUrl}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: publishableKey, 'content-type': 'application/json' },
    body: JSON.stringify({ email: `${randomUUID()}@example.com`, password: randomUUID() }),
  });
  const body = SignUp.parse(await response.json());
  return { token: body.access_token, userId: body.user.id };
}

async function getMe(headers: Record<string, string>, supabaseUrl = config.supabaseUrl) {
  const db = createDatabase(config.databaseUrl);
  const app = createApp({
    db,
    verifyToken: createSupabaseTokenVerifier({ supabaseUrl }),
    checkIns: createCheckIns({ store: createPostgresCheckInStore(db), clock: () => new Date() }),
    log: createLog(() => undefined),
  });
  try {
    const response = await app.request('/me', { headers });
    return [response.status, await response.json()];
  } finally {
    await db.destroy();
  }
}

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
      { version: 1, userId },
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
