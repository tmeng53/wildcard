import { createServer, type Server } from 'node:http';
import { randomUUID, webcrypto, type JsonWebKey } from 'node:crypto';

import { sign } from 'hono/jwt';
import { sql } from 'kysely';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { UserId } from '../ports.js';
import { config, signOut, signUp } from '../test-kit/local-supabase.js';
import { createDatabase } from './postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from './supabase-auth.js';

// A stand-in issuer serving a JWKS whose private keys the test holds, so it can sign tokens
// local Supabase never would (expired, wrong audience) and rotate keys. GET /me's tests cover
// real Supabase tokens.
let server: Server;
let supabaseUrl: string;
let published: JsonWebKey[] = [];
let fetches = 0;

beforeAll(async () => {
  server = createServer((_request, response) => {
    fetches += 1;
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify({ keys: published }));
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (address === null || typeof address === 'string') throw new Error('not listening on TCP');
  supabaseUrl = `http://127.0.0.1:${String(address.port)}`;
});
afterAll(() => {
  server.close();
});

async function newKey() {
  const kid = randomUUID();
  const pair = await webcrypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
    'sign',
    'verify',
  ]);
  const publicKey = {
    ...(await webcrypto.subtle.exportKey('jwk', pair.publicKey)),
    kid,
    alg: 'ES256',
  };
  const privateKey = {
    ...(await webcrypto.subtle.exportKey('jwk', pair.privateKey)),
    kid,
    alg: 'ES256',
  };
  return { kid, publicKey, privateKey };
}

const userId = '11d0042d-1e3c-4c84-9a5f-e61c0a24f8b3';
const inAnHour = () => Math.floor(Date.now() / 1000) + 3600;

async function token(
  key: Awaited<ReturnType<typeof newKey>>,
  claims: Record<string, unknown> = {},
) {
  return sign(
    {
      iss: `${supabaseUrl}/auth/v1`,
      aud: 'authenticated',
      role: 'authenticated',
      sub: userId,
      exp: inAnHour(),
      ...claims,
    },
    key.privateKey,
    'ES256',
  );
}

async function reasonFor(verify: (token: string) => Promise<unknown>, jwt: string) {
  try {
    return await verify(jwt);
  } catch (error) {
    return error instanceof Error && 'reason' in error ? error.reason : error;
  }
}

describe('createSupabaseTokenVerifier', () => {
  it('accepts a current token signed by a published key', async () => {
    const key = await newKey();
    published = [key.publicKey];
    const verify = createSupabaseTokenVerifier({ supabaseUrl });
    expect(await verify(await token(key))).toStrictEqual({ userId });
  });

  it.each([
    ['expired', { exp: Math.floor(Date.now() / 1000) - 1 }],
    ['without an expiry', { exp: undefined }],
    ['for another audience', { aud: 'anon' }],
    ['with the anon role', { role: 'anon' }],
    ['from another issuer', { iss: 'https://other.supabase.co/auth/v1' }],
    ['whose subject is not a user id', { sub: 'service' }],
  ])('refuses a token %s', async (_case, claims) => {
    const key = await newKey();
    published = [key.publicKey];
    const verify = createSupabaseTokenVerifier({ supabaseUrl });
    expect(await reasonFor(verify, await token(key, claims))).toBe('AUTH_TOKEN_INVALID');
  });

  it('refuses a token signed by a key that is not published', async () => {
    published = [(await newKey()).publicKey];
    const verify = createSupabaseTokenVerifier({ supabaseUrl });
    expect(await reasonFor(verify, await token(await newKey()))).toBe('AUTH_TOKEN_INVALID');
  });

  it('fetches the keys once, and again for a new key only after the cooldown', async () => {
    let now = 0;
    const first = await newKey();
    published = [first.publicKey];
    const verify = createSupabaseTokenVerifier({ supabaseUrl, now: () => now });
    fetches = 0;

    await verify(await token(first));
    await verify(await token(first));
    const second = await newKey();
    published = [first.publicKey, second.publicKey];
    now = 10_000;
    const tooSoon = await reasonFor(verify, await token(second));
    now = 31_000;
    const afterCooldown = await reasonFor(verify, await token(second));

    expect({ fetches, tooSoon, afterCooldown }).toStrictEqual({
      fetches: 2,
      tooSoon: 'AUTH_TOKEN_INVALID',
      afterCooldown: { userId },
    });
  });

  it('stops accepting a revoked key once the cached keys are ten minutes old', async () => {
    let now = 0;
    const revoked = await newKey();
    published = [revoked.publicKey];
    const verify = createSupabaseTokenVerifier({ supabaseUrl, now: () => now });
    const jwt = await token(revoked);

    const before = await reasonFor(verify, jwt);
    published = [];
    now = 9 * 60 * 1000;
    const within = await reasonFor(verify, jwt);
    now = 10 * 60 * 1000 + 1;
    const after = await reasonFor(verify, jwt);

    expect({ before, within, after }).toStrictEqual({
      before: { userId },
      within: { userId },
      after: 'AUTH_TOKEN_INVALID',
    });
  });
});

// Against local Supabase Auth.
describe('createSupabaseAccounts', () => {
  const accounts = createSupabaseAccounts({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  });
  const reasonOf = async (promise: Promise<unknown>) => {
    try {
      return await promise;
    } catch (error) {
      return error instanceof Error && 'reason' in error ? error.reason : error;
    }
  };

  it('accepts a current session, and refuses it once signed out', async () => {
    const { token, userId } = await signUp();
    expect(await accounts.verifySession(token)).toStrictEqual({ userId });
    await signOut(token);
    expect(await reasonOf(accounts.verifySession(token))).toBe('AUTH_TOKEN_INVALID');
  });

  it('refuses what isn’t a token', async () => {
    expect(await reasonOf(accounts.verifySession('not-a-jwt'))).toBe('AUTH_TOKEN_INVALID');
  });

  it('deletes a user, whose session then stops working, and a repeat is fine', async () => {
    const { token, userId } = await signUp();
    await accounts.deleteUser(UserId.parse(userId));
    expect(await reasonOf(accounts.verifySession(token))).toBe('AUTH_TOKEN_INVALID');
    await accounts.deleteUser(UserId.parse(userId));
  });

  it('says whether a user signs in with Apple, from their linked identities', async () => {
    const { userId } = await signUp();
    const id = UserId.parse(userId);
    const before = await accounts.signsInWithApple(id);
    const db = createDatabase(config.databaseUrl);
    try {
      await sql`insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at, last_sign_in_at)
        values (${randomUUID()}, ${userId}, '{}'::jsonb, 'apple', now(), now(), now())`.execute(db);
    } finally {
      await db.destroy();
    }
    const after = await accounts.signsInWithApple(id);
    await accounts.deleteUser(id);
    expect([before, after, await accounts.signsInWithApple(id)]).toStrictEqual([
      false,
      true,
      false,
    ]);
  });

  it('says Auth is unavailable when it can’t be reached or refuses the secret key', async () => {
    const { token, userId } = await signUp();
    // Nothing listens on port 1.
    const unreachable = createSupabaseAccounts({
      supabaseUrl: 'http://127.0.0.1:1',
      secretKey: config.supabaseSecretKey,
    });
    const wrongKey = createSupabaseAccounts({
      supabaseUrl: config.supabaseUrl,
      secretKey: 'sb_secret_not-the-key',
    });
    expect(
      await Promise.all([
        reasonOf(unreachable.verifySession(token)),
        reasonOf(unreachable.deleteUser(UserId.parse(userId))),
        reasonOf(wrongKey.deleteUser(UserId.parse(userId))),
        reasonOf(wrongKey.signsInWithApple(UserId.parse(userId))),
      ]),
    ).toStrictEqual([
      'AUTH_UNAVAILABLE',
      'AUTH_UNAVAILABLE',
      'AUTH_UNAVAILABLE',
      'AUTH_UNAVAILABLE',
    ]);
  });
});
