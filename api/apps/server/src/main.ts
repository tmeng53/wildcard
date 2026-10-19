import { serve } from '@hono/node-server';
import { createCheckIns, createPostgresCheckInStore } from '@wildcard/check-ins';
import {
  DisclaimerWriterUnavailableError,
  createDisclaimerDrafts,
  createPostgresDraftAllowance,
  type LanguageModel,
} from '@wildcard/disclaimer-drafts';

import { createAnthropicLanguageModel } from './adapters/anthropic-language-model.js';

import { createDatabase } from './adapters/postgres.js';
import { createSupabaseTokenVerifier } from './adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from './adapters/supabase-storage.js';
import { createApp } from './app.js';
import { readConfig } from './config.js';
import { createLog } from './log.js';

// The composition root: picks the real adapters and serves the API.
const config = readConfig(process.env);
const log = createLog((line) => process.stdout.write(line));
const db = createDatabase(config.databaseUrl);
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
// Without a key every request for drafts fails, so the app shows its dice.
const model: LanguageModel =
  config.anthropicApiKey === undefined
    ? { answer: () => Promise.reject(new DisclaimerWriterUnavailableError()) }
    : createAnthropicLanguageModel({ apiKey: config.anthropicApiKey });
if (config.anthropicApiKey === undefined) log.info('no ANTHROPIC_API_KEY: AI drafts are off');
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  checkIns: createCheckIns({
    store: createPostgresCheckInStore(db),
    photos,
    clock: () => new Date(),
  }),
  photos,
  disclaimerDrafts: createDisclaimerDrafts({
    model,
    // The meme library (api/packages/memes) plugs in here once it lands.
    memes: () => Promise.resolve([]),
    allowance: createPostgresDraftAllowance(db),
    clock: () => new Date(),
  }),
  log,
});

const server = serve({ fetch: app.fetch, port: config.port }, (info) => {
  log.info('listening', { port: info.port });
});

// Cloud Run sends SIGTERM before stopping an instance: finish open requests, then close the pool.
process.once('SIGTERM', () => {
  log.info('shutting down');
  server.close(() => {
    void db.destroy();
  });
});
