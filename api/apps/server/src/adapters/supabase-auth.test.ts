import { createServer, type Server } from 'node:http';
import { randomUUID, webcrypto, type JsonWebKey } from 'node:crypto';

import { sign } from 'hono/jwt';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createSupabaseTokenVerifier } from './supabase-auth.js';

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
