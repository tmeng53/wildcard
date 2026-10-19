import { generateKeyPairSync } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { readConfig } from './config.js';

const base = {
  DATABASE_URL: 'postgres://localhost/wildcard',
  SUPABASE_URL: 'http://127.0.0.1:54321',
  SUPABASE_SECRET_KEY: 'sb_secret_test',
};
const privateKey = generateKeyPairSync('ec', { namedCurve: 'P-256' })
  .privateKey.export({ type: 'pkcs8', format: 'pem' })
  .toString();
const apns = {
  APNS_KEY_ID: 'ABC123DEFG',
  APNS_TEAM_ID: 'TEAM123456',
  APNS_PRIVATE_KEY: privateKey,
  APNS_TOPIC: 'app.wildcard.ios',
};

describe('readConfig', () => {
  it('leaves pushes off with no APNs settings', () => {
    expect(readConfig(base).apns).toBeUndefined();
  });

  it('reads all four APNs settings, with the key’s line breaks given as \\n', () => {
    expect(
      readConfig({ ...base, ...apns, APNS_PRIVATE_KEY: privateKey.replaceAll('\n', '\\n') }).apns,
    ).toStrictEqual({
      keyId: 'ABC123DEFG',
      teamId: 'TEAM123456',
      privateKey,
      topic: 'app.wildcard.ios',
    });
  });

  it('refuses to start with only some APNs settings', () => {
    const three = {
      APNS_KEY_ID: apns.APNS_KEY_ID,
      APNS_TEAM_ID: apns.APNS_TEAM_ID,
      APNS_PRIVATE_KEY: apns.APNS_PRIVATE_KEY,
    };
    expect(() => readConfig({ ...base, ...three })).toThrow(
      'set all of APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_TOPIC or none (missing APNS_TOPIC)',
    );
  });

  it('refuses a private key that isn’t a PEM key', () => {
    expect(() => readConfig({ ...base, ...apns, APNS_PRIVATE_KEY: 'not a key' })).toThrow(
      'Bad server environment',
    );
  });
});
