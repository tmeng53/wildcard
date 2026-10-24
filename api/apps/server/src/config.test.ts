import { generateKeyPairSync } from 'node:crypto';

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
  APPLE_CLIENT_ID: 'com.wildcardsquad.wildcard',
};
const privateKey = generateKeyPairSync('ec', { namedCurve: 'P-256' })
  .privateKey.export({ type: 'pkcs8', format: 'pem' })
  .toString();
const apns = {
  APNS_TEAM_ID: 'TEAM123456',
  APNS_TOPIC: 'com.wildcardsquad.wildcard',
  APNS_SANDBOX_KEY_ID: 'SBX123DEFG',
  APNS_SANDBOX_PRIVATE_KEY: privateKey,
  APNS_PRODUCTION_KEY_ID: 'PRD123DEFG',
  APNS_PRODUCTION_PRIVATE_KEY: privateKey,
};

describe('readConfig', () => {
  it('runs without a Sign in with Apple key or an APNs key until there is one', () => {
    expect(readConfig(base)).toStrictEqual({
      port: 8080,
      databaseUrl: base.DATABASE_URL,
      databaseCaFile: undefined,
      supabaseUrl: 'http://127.0.0.1:54321',
      supabaseSecretKey: 'sb_secret_local',
      publicUrl: new URL('http://localhost:8080'),
      adminPasswordSignIn: false,
      proxyHops: 1,
      languageModelKeys: { openai: undefined, anthropic: undefined },
      appleSignInKey: undefined,
      scheduler: undefined,
      apns: undefined,
      errorReports: undefined,
    });
  });

  it('reports errors only once there is a DSN, naming the revision Cloud Run serves', () => {
    const dsn = 'https://public@o1.ingest.us.sentry.io/2';
    expect(
      readConfig({ ...base, SENTRY_DSN_API: dsn, K_REVISION: 'wildcard-api-00042-abc' })
        .errorReports,
    ).toStrictEqual({
      dsn,
      release: 'wildcard-api-00042-abc',
    });
    expect(readConfig({ ...base, SENTRY_DSN_API: dsn }).errorReports).toStrictEqual({
      dsn,
      release: undefined,
    });
    expect(() => readConfig({ ...base, SENTRY_DSN_API: 'not a url' })).toThrow(/SENTRY_DSN_API/);
  });

  it('keeps each provider’s key, and no longer reads which model writes what', () => {
    const keys = { OPENAI_API_KEY: 'sk-openai', ANTHROPIC_API_KEY: 'sk-ant' };
    expect(readConfig({ ...base, ...keys }).languageModelKeys).toStrictEqual({
      openai: 'sk-openai',
      anthropic: 'sk-ant',
    });
    expect(readConfig({ ...base, ANTHROPIC_API_KEY: 'sk-ant' }).languageModelKeys).toStrictEqual({
      openai: undefined,
      anthropic: 'sk-ant',
    });
    // The model is a setting in the database now: a leftover variable changes nothing.
    expect(
      readConfig({ ...base, LLM_PROVIDER: 'gemini' }).languageModelKeys.openai,
    ).toBeUndefined();
  });

  it('takes Cloud Scheduler’s account over a jobs token, and either alone', () => {
    const token = 'a'.repeat(32);
    const account = 'wildcard-scheduler@project.iam.gserviceaccount.com';
    expect(readConfig({ ...base, JOBS_TOKEN: token }).scheduler).toStrictEqual({
      kind: 'token',
      token,
    });
    expect(
      readConfig({ ...base, JOBS_TOKEN: token, JOBS_SCHEDULER_ACCOUNT: account }).scheduler,
    ).toStrictEqual({ kind: 'google', serviceAccount: account });
    expect(() => readConfig({ ...base, JOBS_SCHEDULER_ACCOUNT: 'not an email' })).toThrow(
      /JOBS_SCHEDULER_ACCOUNT/,
    );
  });

  it('reads the key, with a one-line PEM’s line breaks restored', () => {
    expect(readConfig({ ...base, ...apple }).appleSignInKey).toStrictEqual({
      teamId: 'TEAM123456',
      keyId: 'KEY1234567',
      privateKey: '-----BEGIN PRIVATE KEY-----\nMIGT\n-----END PRIVATE KEY-----',
      clientId: 'com.wildcardsquad.wildcard',
    });
  });

  it('refuses settings in the database URL once a CA file is given', () => {
    for (const query of ['?sslmode=no-verify', '?ssl=no-verify', '?ssl=0']) {
      expect(() =>
        readConfig({
          ...base,
          DATABASE_URL: `${base.DATABASE_URL}${query}`,
          DATABASE_CA_FILE: '/certs/ca.crt',
        }),
      ).toThrow('DATABASE_URL has a query string, whose settings would override DATABASE_CA_FILE');
    }
    expect(readConfig({ ...base, DATABASE_CA_FILE: '/certs/ca.crt' }).databaseCaFile).toBe(
      '/certs/ca.crt',
    );
  });

  it('refuses part of the key', () => {
    expect(() => readConfig({ ...base, ...apple, APPLE_CLIENT_ID: undefined })).toThrow(
      'set all of APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY, APPLE_CLIENT_ID, or none',
    );
  });

  it('reads the Sandbox and Production APNs keys, with line breaks given as \\n', () => {
    expect(
      readConfig({
        ...base,
        ...apns,
        APNS_SANDBOX_PRIVATE_KEY: privateKey.replaceAll('\n', '\\n'),
      }).apns,
    ).toStrictEqual({
      teamId: 'TEAM123456',
      topic: 'com.wildcardsquad.wildcard',
      keys: {
        sandbox: { keyId: 'SBX123DEFG', privateKey },
        production: { keyId: 'PRD123DEFG', privateKey },
      },
    });
  });

  it('refuses to start with only some APNs settings, such as no Production key', () => {
    expect(() =>
      readConfig({
        ...base,
        ...apns,
        APNS_PRODUCTION_KEY_ID: undefined,
        APNS_PRODUCTION_PRIVATE_KEY: undefined,
      }),
    ).toThrow(
      'set all of APNS_TEAM_ID, APNS_TOPIC, APNS_SANDBOX_KEY_ID, APNS_SANDBOX_PRIVATE_KEY, APNS_PRODUCTION_KEY_ID, APNS_PRODUCTION_PRIVATE_KEY or none (missing APNS_PRODUCTION_KEY_ID, APNS_PRODUCTION_PRIVATE_KEY)',
    );
  });

  it('refuses an APNs private key that isn’t a PEM key', () => {
    expect(() =>
      readConfig({ ...base, ...apns, APNS_PRODUCTION_PRIVATE_KEY: 'not a key' }),
    ).toThrow('Bad server environment');
  });
});
