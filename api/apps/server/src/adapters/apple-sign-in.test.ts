import { createServer, type Server } from 'node:http';
import { generateKeyPairSync, verify } from 'node:crypto';

import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createAppleSignInRevoker } from './apple-sign-in.js';

// A stand-in for appleid.apple.com that checks each client secret against the public half of
// a key the test made, the way Apple checks it against the team's key. Apple itself can't be
// called without a real key and a real sign-in.
const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const key = {
  teamId: 'TEAM123456',
  keyId: 'KEY1234567',
  privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
  clientId: 'app.wildcard.ios',
};
const NOW = 1_800_000_000_000;

interface Seen {
  readonly path: string | undefined;
  readonly form: Record<string, string>;
}
let server: Server;
let appleUrl: string;
let seen: Seen[] = [];
/** How the stand-in answers the code exchange. */
let exchange: { status: number; body: unknown } = { status: 200, body: {} };

beforeAll(async () => {
  server = createServer((request, response) => {
    let text = '';
    request.on('data', (chunk: Buffer) => (text += chunk.toString()));
    request.on('end', () => {
      seen.push({ path: request.url, form: Object.fromEntries(new URLSearchParams(text)) });
      response.setHeader('content-type', 'application/json');
      if (request.url === '/auth/token') {
        response.statusCode = exchange.status;
        response.end(JSON.stringify(exchange.body));
      } else {
        response.end();
      }
    });
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (address === null || typeof address === 'string') throw new Error('not listening on TCP');
  appleUrl = `http://127.0.0.1:${String(address.port)}`;
});
afterAll(() => {
  server.close();
});
beforeEach(() => {
  seen = [];
  exchange = { status: 200, body: { access_token: 'a', refresh_token: 'r3fresh', id_token: 'i' } };
});

const revoke = (code: string) =>
  createAppleSignInRevoker({ ...key, appleUrl, now: () => NOW })(code);

async function reasonOf(promise: Promise<unknown>) {
  try {
    return await promise;
  } catch (error) {
    return error instanceof Error && 'reason' in error ? error.reason : error;
  }
}

/** The client secret's header and claims, after checking its ES256 signature. */
function readSecret(secret: string | undefined) {
  const [header = '', claims = '', signature = ''] = (secret ?? '').split('.');
  const signed = verify(
    'sha256',
    Buffer.from(`${header}.${claims}`),
    { key: publicKey, dsaEncoding: 'ieee-p1363' },
    Buffer.from(signature, 'base64url'),
  );
  const json = (part: string): unknown => JSON.parse(Buffer.from(part, 'base64url').toString());
  return { signed, header: json(header), claims: json(claims) };
}

describe('createAppleSignInRevoker', () => {
  it('trades the code for a refresh token, then revokes it, with a signed client secret', async () => {
    await revoke('c0de');
    expect(seen.map(({ path, form }) => ({ path, ...form, client_secret: '…' }))).toStrictEqual([
      {
        path: '/auth/token',
        client_id: 'app.wildcard.ios',
        client_secret: '…',
        code: 'c0de',
        grant_type: 'authorization_code',
      },
      {
        path: '/auth/revoke',
        client_id: 'app.wildcard.ios',
        client_secret: '…',
        token: 'r3fresh',
        token_type_hint: 'refresh_token',
      },
    ]);
    const secret = z.string().parse(seen[0]?.form.client_secret);
    expect(readSecret(secret)).toStrictEqual({
      signed: true,
      header: { alg: 'ES256', kid: 'KEY1234567' },
      claims: {
        iss: 'TEAM123456',
        iat: 1_800_000_000,
        exp: 1_800_000_300,
        aud: 'https://appleid.apple.com',
        sub: 'app.wildcard.ios',
      },
    });
  });

  it('says a code Apple refuses is invalid, and revokes nothing', async () => {
    exchange = { status: 400, body: { error: 'invalid_grant' } };
    expect(await reasonOf(revoke('expired'))).toBe('APPLE_AUTHORIZATION_CODE_INVALID');
    expect(seen.map(({ path }) => path)).toStrictEqual(['/auth/token']);
  });

  it.each([
    ['another 400', { status: 400, body: { error: 'invalid_client' } }],
    ['a 500', { status: 500, body: {} }],
  ])('says Apple is unavailable on %s', async (_case, answer) => {
    exchange = answer;
    expect(await reasonOf(revoke('c0de'))).toBe('APPLE_SIGN_IN_UNAVAILABLE');
  });

  it('says Apple is unavailable when it can’t be reached', async () => {
    // Nothing listens on port 1.
    const unreachable = createAppleSignInRevoker({ ...key, appleUrl: 'http://127.0.0.1:1' });
    expect(await reasonOf(unreachable('c0de'))).toBe('APPLE_SIGN_IN_UNAVAILABLE');
  });

  it('refuses a key that isn’t one, when the server starts', () => {
    expect(() => createAppleSignInRevoker({ ...key, privateKey: 'not a key' })).toThrow();
  });
});
