import { readFileSync } from 'node:fs';

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
  createPostgresReplyStore,
  createPostgresWeekSummaryWords,
  createPostgresWeeklyPlanStore,
  createWeekSummaryWords,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import {
  DisclaimerWriterOffError,
  createDisclaimerDrafts,
  createDraftSettings,
  createPostgresDraftAllowance,
  createPostgresDraftSettings,
} from '@wildcard/disclaimer-drafts';
import {
  createMembers,
  createPostgresProfileStore,
  MemberId as ProfileMember,
} from '@wildcard/members';
import { createMemes, createPostgresMemeStore } from '@wildcard/memes';
import { createNudges, createPostgresNudgeStore } from '@wildcard/nudges';
import {
  createApnsSender,
  createOffSender,
  createDailyPushSettings,
  createPostgresDailyPushSettings,
  createPostgresDailyPushStore,
  createPostgresDeviceStore,
  createPostgresSettingsStore,
  createPush,
} from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import {
  AwardsModelMissingError,
  AwardsWriterUnavailableError,
  createAwardSettings,
  createPostgresAwardSettings,
  createPostgresAwardsStore,
  createWeeklyAwards,
} from '@wildcard/weekly-awards';

import { createAnthropicLanguageModel } from './adapters/anthropic-language-model.js';
import { byProvider } from './adapters/language-models.js';
import { createOpenAILanguageModel } from './adapters/openai-language-model.js';
import { createMemoryRateLimit } from './adapters/memory-rate-limit.js';
import { createDatabase } from './adapters/postgres.js';
import { createAppleSignInRevoker } from './adapters/apple-sign-in.js';
import {
  createSupabaseAccounts,
  createSupabaseTokenVerifier,
  supabaseAuthIssuer,
} from './adapters/supabase-auth.js';
import { googleScheduler, jobsTokenScheduler } from './adapters/scheduler.js';
import { createSupabaseOAuthConsent } from './adapters/supabase-oauth-consent.js';
import { listAdminLog } from './admin-mcp/tools/admin-log.js';
import { aiWritingTools } from './admin-mcp/tools/ai-writing.js';
import { dailyPushTools } from './admin-mcp/tools/daily-push.js';
import { weekSummaryWordTools } from './admin-mcp/tools/week-summary-words.js';
import { nudgeInteractions, reactionInteractions } from './flows/daily-progress-push.js';
import { memeTools } from './admin-mcp/tools/memes.js';
import { createSentryErrorReports } from './adapters/sentry.js';
import { createSupabasePhotoStorage } from './adapters/supabase-storage.js';
import { createApp } from './app.js';
import { readConfig } from './config.js';
import { createLog, redactText, reportingErrors } from './log.js';
import { memberCalendar } from './member-calendar.js';
import type { Database } from './ports.js';

// The composition root: picks the real adapters and serves the API.
const config = readConfig(process.env);
// Every error the server logs also goes to Sentry, once the API project's DSN is set.
const errorReports =
  config.errorReports === undefined
    ? undefined
    : createSentryErrorReports({ ...config.errorReports, redact: redactText });
const stdoutLog = createLog((line) => process.stdout.write(line), {
  traceProject: config.traceProject,
});
const log = errorReports === undefined ? stdoutLog : reportingErrors(stdoutLog, errorReports);
if (errorReports === undefined) log.info('no Sentry DSN (SENTRY_DSN_API): errors are only logged');
const db = createDatabase(config.databaseUrl, {
  ca: config.databaseCaFile === undefined ? undefined : readFileSync(config.databaseCaFile, 'utf8'),
  onIdleError: (error) => {
    log.warn('the database dropped an idle connection', { error });
  },
});
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
// Each module's settings (in the database) name the model that writes for it; it goes to that
// model's provider, if the server has its key. Without one, drafts are off (the app shows its
// dice) and the weekly awards stay pending.
const { openai: openaiKey, anthropic: anthropicKey } = config.languageModelKeys;
const providers = (options: {
  readonly timeoutMs?: number;
  readonly maxOutputTokens?: number;
}) => ({
  ...(openaiKey === undefined
    ? {}
    : { openai: createOpenAILanguageModel({ apiKey: openaiKey, ...options }) }),
  ...(anthropicKey === undefined
    ? {}
    : { anthropic: createAnthropicLanguageModel({ apiKey: anthropicKey, ...options }) }),
});
const model = byProvider(providers({}), () => new DisclaimerWriterOffError());
// The awards are written in a job nobody waits on: a longer answer, given more time.
const awardsModel = byProvider(
  providers({ timeoutMs: 120_000, maxOutputTokens: 16_384 }),
  () => new AwardsWriterUnavailableError({ cause: new AwardsModelMissingError() }),
);
if (openaiKey === undefined && anthropicKey === undefined) {
  log.info('no language model key: AI drafts are off and weekly awards stay pending');
}
const memes = createMemes({ store: createPostgresMemeStore(db), clock: () => new Date() });
if (config.appleSignInKey === undefined) {
  log.warn('No Sign in with Apple key: deleted accounts keep their Apple sign-in grant');
}
const members = createMembers({ store: createPostgresProfileStore(db) });
const push = createPush({
  store: createPostgresDeviceStore(db),
  settings: createPostgresSettingsStore(db),
  daily: createPostgresDailyPushStore(db),
  dailySettings: createPostgresDailyPushSettings(db),
  sender: config.apns === undefined ? createOffSender() : createApnsSender(config.apns),
});
if (config.apns === undefined) log.info('push notifications are off: no APNs key');
// The admin tools get a database or a transaction of it: each change commits with its log row.
const adminsOn = (scope: Database) =>
  createAdmins({ store: createPostgresAdminStore(scope), clock: () => new Date() });
// What members agree to before their words go to AI providers: the current version of the app's
// copy, which names them. Squads, drafts and the weekly awards ask it.
const aiConsent = createAiConsent({
  store: createPostgresConsentStore(db),
  copyVersion: AI_CONSENT_COPY_VERSION,
  clock: () => new Date(),
});
const hasAiConsent = (member: string) => aiConsent.hasCurrent(ConsentMember.parse(member));
const awards = createWeeklyAwards({
  model: awardsModel,
  settings: createPostgresAwardSettings(db),
  store: createPostgresAwardsStore(db),
  aiConsented: (members) =>
    aiConsent.currentAmong(members.map((member) => ConsentMember.parse(member))),
});
// The scheduler that starts jobs: Cloud Scheduler's signed token on the hosted server, a shared
// token on a local one.
const isScheduler =
  config.scheduler?.kind === 'google'
    ? googleScheduler({
        serviceAccount: config.scheduler.serviceAccount,
        audience: config.publicUrl.origin,
      })
    : config.scheduler?.kind === 'token'
      ? jobsTokenScheduler(config.scheduler.token)
      : undefined;
if (isScheduler === undefined)
  log.info(
    'no scheduler (JOBS_SCHEDULER_ACCOUNT or JOBS_TOKEN): the daily progress push and weekly awards are off',
  );
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
  replies: createPostgresReplyStore(db),
  plans: createPostgresWeeklyPlanStore(db),
  photos,
  calendarOf: memberCalendar(members),
  clock: () => new Date(),
});
const nudges = createNudges({
  store: createPostgresNudgeStore(db),
  // Who is in which squad is the squads module's to keep: nudges ask it.
  membership: squads,
  timeZoneOf: async (member) => (await members.findProfile(ProfileMember.parse(member)))?.timeZone,
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
  nudges,
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
    settings: createPostgresDraftSettings(db),
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
  weekSummaryWords: () => createPostgresWeekSummaryWords(db).current(),
  weeklyAwards: { awards, clock: () => new Date() },
  log,
  jobs: {
    isScheduler,
    // Each kind of interaction the daily push counts comes from one of these.
    interactions: [reactionInteractions(checkIns), nudgeInteractions(nudges)],
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
      ...aiWritingTools({
        drafts: createDraftSettings({ store: createPostgresDraftSettings(scope) }),
        awards: createAwardSettings({ store: createPostgresAwardSettings(scope) }),
      }),
      ...dailyPushTools({
        settings: createDailyPushSettings({ store: createPostgresDailyPushSettings(scope) }),
      }),
      ...weekSummaryWordTools({
        words: createWeekSummaryWords({ store: createPostgresWeekSummaryWords(scope) }),
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
  // Cloud Run gives an instance 10 seconds after SIGTERM: send the reports still queued.
  void errorReports?.flush(2000);
});
