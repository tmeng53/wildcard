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
  APPLE_CLIENT_ID: 'app.wildcard.ios',
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
      languageModel: undefined,
      appleSignInKey: undefined,
      apns: undefined,
    });
  });

  it('picks OpenAI for drafts unless told otherwise, with the adapter’s default model', () => {
    const keys = { OPENAI_API_KEY: 'sk-openai', ANTHROPIC_API_KEY: 'sk-ant' };
    expect(readConfig({ ...base, ...keys }).languageModel).toStrictEqual({
      provider: 'openai',
      apiKey: 'sk-openai',
      model: undefined,
    });
    expect(
      readConfig({ ...base, ...keys, LLM_PROVIDER: 'anthropic', LLM_MODEL: 'claude-sonnet-5-5' })
        .languageModel,
    ).toStrictEqual({ provider: 'anthropic', apiKey: 'sk-ant', model: 'claude-sonnet-5-5' });
  });

  it('turns drafts off while the chosen provider has no key, and refuses an unknown one', () => {
    expect(readConfig({ ...base, ANTHROPIC_API_KEY: 'sk-ant' }).languageModel).toBeUndefined();
    expect(() => readConfig({ ...base, LLM_PROVIDER: 'gemini' })).toThrow('LLM_PROVIDER');
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

  it('refuses an APNs private key that isn’t a PEM key', () => {
    expect(() => readConfig({ ...base, ...apns, APNS_PRIVATE_KEY: 'not a key' })).toThrow(
      'Bad server environment',
    );
  });
});
