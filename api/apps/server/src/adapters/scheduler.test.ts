import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { createServer } from 'node:http';

import { sign } from 'hono/jwt';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { googleScheduler, jobsTokenScheduler } from './scheduler.js';

describe('the jobs token scheduler', () => {
  it('takes only the exact token', async () => {
    const token = randomBytes(32).toString('hex');
    const isScheduler = jobsTokenScheduler(token);
    expect(await isScheduler(token)).toBe(true);
    expect(await isScheduler(`${token}x`)).toBe(false);
    expect(await isScheduler(randomBytes(32).toString('hex'))).toBe(false);
  });
});

// Google's role played locally: a key pair, its public half served as a JWKS, and ID tokens
// signed with the private half, shaped like the ones Cloud Scheduler sends.
const account = 'wildcard-scheduler@project.iam.gserviceaccount.com';
const audience = 'https://api.wildcardsquad.com';
const keyPair = () => {
  const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  return {
    publicJwk: { ...publicKey.export({ format: 'jwk' }), kid: 'google', alg: 'RS256', use: 'sig' },
    privateJwk: { ...privateKey.export({ format: 'jwk' }), kid: 'google', alg: 'RS256' },
  };
};
const google = keyPair();
const stranger = keyPair();
const keys = createServer((_, response) => {
  response.setHeader('content-type', 'application/json');
  response.end(JSON.stringify({ keys: [google.publicJwk] }));
});
let keysUrl = '';
beforeAll(async () => {
  await new Promise<void>((resolve) => keys.listen(0, '127.0.0.1', resolve));
  const address = keys.address();
  if (address === null || typeof address === 'string') throw new Error('no port to serve keys on');
  keysUrl = `http://127.0.0.1:${String(address.port)}/certs`;
});
afterAll(
  () =>
    new Promise<void>((resolve) => {
      keys.close(() => {
        resolve();
      });
    }),
);

const now = () => Math.floor(Date.now() / 1000);
function idToken(
  claims: Record<string, unknown> = {},
  { key = google.privateJwk }: { key?: object } = {},
) {
  return sign(
    {
      iss: 'https://accounts.google.com',
      aud: audience,
      email: account,
      email_verified: true,
      iat: now() - 10,
      exp: now() + 3_600,
      ...claims,
    },
    key,
    'RS256',
  );
}

describe('the Google scheduler', () => {
  const isScheduler = () => googleScheduler({ serviceAccount: account, audience, keysUrl });

  it('takes an ID token Google signed for this API and the scheduler’s account', async () => {
    expect(await isScheduler()(await idToken())).toBe(true);
    expect(await isScheduler()(await idToken({ iss: 'accounts.google.com' }))).toBe(true);
  });

  it('refuses another account, audience or issuer, an unverified email and an expired token', async () => {
    for (const claims of [
      { email: 'someone@project.iam.gserviceaccount.com' },
      { aud: 'https://elsewhere.example' },
      { iss: 'https://evil.example' },
      { email_verified: false },
      { iat: now() - 7_200, exp: now() - 3_600 },
    ]) {
      expect(await isScheduler()(await idToken(claims))).toBe(false);
    }
  });

  it('refuses a token signed with any other key, and one that isn’t a token', async () => {
    expect(await isScheduler()(await idToken({}, { key: stranger.privateJwk }))).toBe(false);
    expect(await isScheduler()(randomBytes(32).toString('hex'))).toBe(false);
  });

  it('refuses everything while Google’s keys can’t be fetched', async () => {
    const offline = googleScheduler({
      serviceAccount: account,
      audience,
      keysUrl: 'http://127.0.0.1:9/certs',
    });
    expect(await offline(await idToken())).toBe(false);
  });
});
