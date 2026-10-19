import { serve } from '@hono/node-server';
import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import {
  DisclaimerWriterOffError,
  createDisclaimerDrafts,
  createPostgresDraftAllowance,
  type LanguageModel,
} from '@wildcard/disclaimer-drafts';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createMemes, createPostgresMemeStore } from '@wildcard/memes';
import {
  createApnsSender,
  createOffSender,
  createPostgresDeviceStore,
  createPush,
} from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';

import { createAnthropicLanguageModel } from './adapters/anthropic-language-model.js';
import { createDatabase } from './adapters/postgres.js';
import { createAppleSignInRevoker } from './adapters/apple-sign-in.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from './adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from './adapters/supabase-storage.js';
import { createApp } from './app.js';
import { readConfig } from './config.js';
import { createLog } from './log.js';
import { memberCalendar } from './member-calendar.js';

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
    ? { answer: () => Promise.reject(new DisclaimerWriterOffError()) }
    : createAnthropicLanguageModel({ apiKey: config.anthropicApiKey });
if (config.anthropicApiKey === undefined) log.info('no ANTHROPIC_API_KEY: AI drafts are off');
const memes = createMemes({ store: createPostgresMemeStore(db), clock: () => new Date() });
if (config.appleSignInKey === undefined) {
  log.warn('No Sign in with Apple key: deleted accounts keep their Apple sign-in grant');
}
const members = createMembers({ store: createPostgresProfileStore(db) });
const push = createPush({
  store: createPostgresDeviceStore(db),
  sender: config.apns === undefined ? createOffSender() : createApnsSender(config.apns),
});
if (config.apns === undefined) log.info('push notifications are off: no APNs key');
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  accounts: createSupabaseAccounts({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  }),
  revokeAppleSignIn:
    config.appleSignInKey === undefined
      ? undefined
      : createAppleSignInRevoker(config.appleSignInKey),
  checkIns: createCheckIns({
    store: createPostgresCheckInStore(db),
    reactions: createPostgresReactionStore(db),
    photos,
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  weeklyPlans: createWeeklyPlans({
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  members,
  squads: createSquads({ store: createPostgresSquadStore(db), inviteCodes: randomInviteCodes }),
  photos,
  disclaimerDrafts: createDisclaimerDrafts({
    model,
    // Only what the prompt needs: a meme's source and approval stay out of it.
    memes: async () =>
      (await memes.listInUse()).map(({ phrase, meaning, background, styles }) => ({
        phrase,
        meaning,
        background,
        styles,
      })),
    allowance: createPostgresDraftAllowance(db),
    clock: () => new Date(),
  }),
  push,
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
