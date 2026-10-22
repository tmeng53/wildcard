import { serve } from '@hono/node-server';
import { createAdmins, createPostgresAdminStore } from '@wildcard/admins';
import {
  AI_CONSENT_COPY_VERSION,
  MemberId as ConsentMember,
  createAiConsent,
  createPostgresConsentStore,
} from '@wildcard/ai-consent';
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
  createPostgresDailyPushStore,
  createPostgresDeviceStore,
  createPostgresSettingsStore,
  createPush,
} from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';

import { createAnthropicLanguageModel } from './adapters/anthropic-language-model.js';
import { createOpenAILanguageModel } from './adapters/openai-language-model.js';
import { createMemoryRateLimit } from './adapters/memory-rate-limit.js';
import { createDatabase } from './adapters/postgres.js';
import { createAppleSignInRevoker } from './adapters/apple-sign-in.js';
import {
  createSupabaseAccounts,
  createSupabaseTokenVerifier,
  supabaseAuthIssuer,
} from './adapters/supabase-auth.js';
import { createSupabaseOAuthConsent } from './adapters/supabase-oauth-consent.js';
import { listAdminLog } from './admin-mcp/tools/admin-log.js';
import { reactionInteractions } from './flows/daily-progress-push.js';
import { memeTools } from './admin-mcp/tools/memes.js';
import { createSupabasePhotoStorage } from './adapters/supabase-storage.js';
import { createApp } from './app.js';
import { readConfig } from './config.js';
import { createLog } from './log.js';
import { memberCalendar } from './member-calendar.js';
import type { Database } from './ports.js';

// The composition root: picks the real adapters and serves the API.
const config = readConfig(process.env);
const log = createLog((line) => process.stdout.write(line));
const db = createDatabase(config.databaseUrl, {
  onIdleError: (error) => {
    log.warn('the database dropped an idle connection', { error });
  },
});
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
// The provider LLM_PROVIDER names writes drafts. Without its key every request for drafts
// fails, so the app shows its dice.
const llm = config.languageModel;
const model: LanguageModel =
  llm === undefined
    ? { answer: () => Promise.reject(new DisclaimerWriterOffError()) }
    : llm.provider === 'openai'
      ? createOpenAILanguageModel({ apiKey: llm.apiKey, model: llm.model })
      : createAnthropicLanguageModel({ apiKey: llm.apiKey, model: llm.model });
if (llm === undefined) log.info('no key for LLM_PROVIDER: AI drafts are off');
const memes = createMemes({ store: createPostgresMemeStore(db), clock: () => new Date() });
if (config.appleSignInKey === undefined) {
  log.warn('No Sign in with Apple key: deleted accounts keep their Apple sign-in grant');
}
const members = createMembers({ store: createPostgresProfileStore(db) });
const push = createPush({
  store: createPostgresDeviceStore(db),
  settings: createPostgresSettingsStore(db),
  daily: createPostgresDailyPushStore(db),
  sender: config.apns === undefined ? createOffSender() : createApnsSender(config.apns),
});
if (config.apns === undefined) log.info('push notifications are off: no APNs key');
// The admin tools get a database or a transaction of it: each change commits with its log row.
const adminsOn = (scope: Database) =>
  createAdmins({ store: createPostgresAdminStore(scope), clock: () => new Date() });
// What members agree to before their words go to AI providers: the current version of the app's
// copy, which names them. Squads and drafts ask it.
const aiConsent = createAiConsent({
  store: createPostgresConsentStore(db),
  copyVersion: AI_CONSENT_COPY_VERSION,
  clock: () => new Date(),
});
const hasAiConsent = (member: string) => aiConsent.hasCurrent(ConsentMember.parse(member));
if (config.jobsToken === undefined) log.info('no JOBS_TOKEN: the daily progress push is off');
const squads = createSquads({
  store: createPostgresSquadStore(db),
  inviteCodes: randomInviteCodes,
  aiConsent: hasAiConsent,
});
const checkIns = createCheckIns({
  store: createPostgresCheckInStore(db),
  // Who is in which squad is the squads module's to keep: check-ins ask it.
  membership: squads,
  reactions: createPostgresReactionStore(db),
  plans: createPostgresWeeklyPlanStore(db),
  photos,
  calendarOf: memberCalendar(members),
  clock: () => new Date(),
});
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
  checkIns,
  weeklyPlans: createWeeklyPlans({
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  members,
  squads,
  aiConsent,
  publicRoutes: {
    proxyHops: config.proxyHops,
    // Someone opening an invite link looks it up a few times at most; guessing a code takes
    // billions of tries, so this only keeps the lookup from being hammered.
    inviteLookups: createMemoryRateLimit({
      limit: 30,
      windowSeconds: 600,
      clock: () => new Date(),
    }),
  },
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
    aiConsent: hasAiConsent,
    clock: () => new Date(),
    random: Math.random,
  }),
  push,
  log,
  jobs: {
    token: config.jobsToken,
    // Each kind of interaction the daily push counts comes from one of these.
    interactions: [reactionInteractions(checkIns)],
    clock: () => new Date(),
  },
  admin: {
    admins: adminsOn,
    tools: (scope) => [
      listAdminLog({ admins: adminsOn(scope) }),
      ...memeTools({
        memes: createMemes({ store: createPostgresMemeStore(scope), clock: () => new Date() }),
        clock: () => new Date(),
      }),
    ],
    publicUrl: config.publicUrl,
    authorizationServer: supabaseAuthIssuer(config.supabaseUrl),
    consent: createSupabaseOAuthConsent({
      supabaseUrl: config.supabaseUrl,
      secretKey: config.supabaseSecretKey,
    }),
    passwordSignIn: config.adminPasswordSignIn,
  },
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
