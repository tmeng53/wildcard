import { describe, expect, it } from 'vitest';

import { readConfig } from './config.js';

const base = {
  DATABASE_URL: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres',
  SUPABASE_URL: 'http://127.0.0.1:54321/',
  SUPABASE_SECRET_KEY: 'sb_secret_local',
};
const apple = {
  APPLE_TEAM_ID: 'TEAM123456',
  APPLE_KEY_ID: 'KEY1234567',
  APPLE_PRIVATE_KEY: '-----BEGIN PRIVATE KEY-----\\nMIGT\\n-----END PRIVATE KEY-----',
  APPLE_CLIENT_ID: 'app.wildcard.ios',
};

describe('readConfig', () => {
  it('runs without a Sign in with Apple key until there is one', () => {
    expect(readConfig(base)).toStrictEqual({
      port: 8080,
      databaseUrl: base.DATABASE_URL,
      supabaseUrl: 'http://127.0.0.1:54321',
      supabaseSecretKey: 'sb_secret_local',
      publicUrl: new URL('http://localhost:8080'),
      appleSignInKey: undefined,
    });
  });

  it('reads the key, with a one-line PEM’s line breaks restored', () => {
    expect(readConfig({ ...base, ...apple }).appleSignInKey).toStrictEqual({
      teamId: 'TEAM123456',
      keyId: 'KEY1234567',
      privateKey: '-----BEGIN PRIVATE KEY-----\nMIGT\n-----END PRIVATE KEY-----',
      clientId: 'app.wildcard.ios',
    });
  });

  it('refuses part of the key', () => {
    expect(() => readConfig({ ...base, ...apple, APPLE_CLIENT_ID: undefined })).toThrow(
      'set all of APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY, APPLE_CLIENT_ID, or none',
    );
  });
});
