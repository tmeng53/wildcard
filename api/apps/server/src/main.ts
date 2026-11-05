import { readFileSync } from 'node:fs';

import { serve } from '@hono/node-server';
import { createAdmins, createPostgresAdminStore } from '@wildcard/admins';
import {
  AI_CONSENT_COPY_VERSION,
  MemberId as ConsentMember,
  createAiConsent,
  createPostgresConsentStore,
} from '@wildcard/ai-consent';
import { createArt, createPostgresArtStore } from '@wildcard/art';
import {
  MemberId as CheckInMember,
  PhotoPath,
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeekSummaryWords,
  createPostgresWeeklyPlanStore,
  createWeekSummaryWords,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import {
  createCoachCatalog,
  createCoachHiring,
  createCoachActivity,
  createCoachSettings,
  createCoachNoteDelivery,
  createCoachWakes,
  createPostgresCoachActivity,
  createPostgresCoachCatalog,
  createPostgresCoachNoteDelivery,
  createPostgresCoachHiring,
  createPostgresCoachReport,
  createPostgresCoachSettings,
  createPostgresCoachStores,
  postgresCoachTransaction,
  SquadId as CoachSquadId,
} from '@wildcard/coach';
import {
  DisclaimerWriterOffError,
  createDisclaimerDrafts,
  createDiceLines,
  createDraftSettings,
  createPostgresDiceLines,
  createPostgresDraftAllowance,
  createPostgresDraftSettings,
} from '@wildcard/disclaimer-drafts';
import {
  createMembers,
  createPostgresProfileStore,
  MemberId as ProfileMember,
} from '@wildcard/members';
import { createMemes, createPostgresMemeStore } from '@wildcard/memes';
import {
  MemberId as NoticeMember,
  SquadId as NoticeSquad,
  createNotices,
  createPostgresBroadcastStore,
  createPostgresNoticeStore,
  type GiveGifts,
  type NewNotice,
} from '@wildcard/notices';
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
  createPostgresWeekStoryStore,
  createWeeklyAwards,
} from '@wildcard/weekly-awards';
import { createPostgresSceneStore, createScenes } from '@wildcard/scenes';
import { createPostgresSwitchStore, createSwitches } from '@wildcard/switches';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import {
  MemberId as UnlockMember,
  createCoachGifts,
  createPostgresGiftStore,
  createPostgresUnlockStore,
  createUnlocks,
} from '@wildcard/unlocks';

import { createAnthropicLanguageModel } from './adapters/anthropic-language-model.js';
import { byProvider } from './adapters/language-models.js';
import { createOpenAICoachAgent } from './adapters/openai-coach-agent.js';
import { createOpenAILanguageModel } from './adapters/openai-language-model.js';
import { createMemoryRateLimit } from './adapters/memory-rate-limit.js';
import { createPostgresLiveEvents } from './adapters/postgres-live-events.js';
import { createDatabase, onItsOwn } from './adapters/postgres.js';
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
import { coachTools } from './admin-mcp/tools/coach.js';
import { dailyPushTools } from './admin-mcp/tools/daily-push.js';
import { disclaimerDiceTools } from './admin-mcp/tools/disclaimer-dice.js';
import { weekSummaryWordTools } from './admin-mcp/tools/week-summary-words.js';
import { coachMemberFacts, coachSquadWeek } from './flows/coach.js';
import { pushCoachLine } from './flows/comment-push.js';
import { nudgeInteractions, checkInInteractions } from './flows/daily-progress-push.js';
import { memeTools } from './admin-mcp/tools/memes.js';
import { sceneTools } from './admin-mcp/tools/scenes.js';
import { switchTools } from './admin-mcp/tools/switches.js';
import { sportTools } from './admin-mcp/tools/sports.js';
import { unlockTools } from './admin-mcp/tools/unlocks.js';
import { broadcastTools } from './admin-mcp/tools/broadcasts.js';
import { artTools } from './admin-mcp/tools/art.js';
import { testPushTools } from './admin-mcp/tools/test-push.js';
import { createSentryErrorReports } from './adapters/sentry.js';
import { createSupabaseArtStorage } from './adapters/supabase-art-storage.js';
import { createSupabasePhotoStorage } from './adapters/supabase-storage.js';
import { createApp } from './app.js';
import {
  artSection,
  disclaimerDiceSection,
  scenesSection,
  sportsSection,
  switchesSection,
  storesSection,
  piecesSection,
} from './routes/catalog.js';
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
const databaseCa =
  config.databaseCaFile === undefined ? undefined : readFileSync(config.databaseCaFile, 'utf8');
const db = createDatabase(config.databaseUrl, {
  ca: databaseCa,
  onIdleError: (error) => {
    log.warn('the database dropped an idle connection', { error });
  },
});
// Members' live events (`GET /me/events`), heard from the database on a session of their own.
const liveEvents = createPostgresLiveEvents(config.liveEventsDatabaseUrl, {
  ...(databaseCa === undefined ? {} : { ca: databaseCa }),
  onLost: (error) => {
    log.warn('lost the live events connection; open streams end and reconnect', { error });
  },
});

// The art apps download: the list in the database, the files in Storage's public bucket.
const artFiles = createSupabaseArtStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const artOn = (scope: Database) =>
  createArt({ store: createPostgresArtStore(scope), blobs: artFiles });
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
  stories: createPostgresWeekStoryStore(db),
  aiConsented: (members) =>
    aiConsent.currentAmong(members.map((member) => ConsentMember.parse(member))),
  // Every meme in use, so the awards can draw on any that fits; only what the prompt needs.
  memes: async () =>
    (await memes.listInUse()).map(({ phrase, meaning, background }) => ({
      phrase,
      meaning,
      background,
    })),
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
// The sports list every picker shows, kept in the database.
const sports = createSports({ store: createPostgresSportStore(db) });
// Global on/off switches (a winter theme, a holiday) that limited scenes, stores and pieces follow.
const switchesOn = (scope: Database) => createSwitches({ store: createPostgresSwitchStore(scope) });
const switches = switchesOn(db);
const scenes = createScenes({
  store: createPostgresSceneStore(db),
  switches: () => switches.states(),
});
// What each squad's coach said; check-ins ask it whether a member may reply to the coach.
const coachActivity = createCoachActivity({ store: createPostgresCoachActivity(db) });
const checkIns = createCheckIns({
  store: createPostgresCheckInStore(db),
  // Who is in which squad is the squads module's to keep: check-ins ask it.
  membership: squads,
  // Which sports exist is the sports module's to keep: check-ins and plans ask it.
  sports,
  reactions: createPostgresReactionStore(db),
  comments: createPostgresCommentStore(db),
  coachSpoke: ({ checkIn, squads: through, coach }) =>
    coachActivity.spoke({
      squads: through.map((squad) => CoachSquadId.parse(squad)),
      checkIn,
      coach,
    }),
  coachHired: async ({ squads: through, coach }) => {
    const hiring = createPostgresCoachHiring(db);
    for (const squad of through) {
      if ((await hiring.coachOf(CoachSquadId.parse(squad)))?.coach === coach) return true;
    }
    return false;
  },
  plans: createPostgresWeeklyPlanStore(db),
  photos,
  calendarOf: memberCalendar(members),
  clock: () => new Date(),
});
const newYorkDays = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
/** What the unlocks module asks other modules, for `unlocksOn` and a broadcast's gifts. */
const unlockSources = (scope: Database) => ({
  store: createPostgresUnlockStore(scope),
  trainedSince: ({ member, since }: { readonly member: string; readonly since: Date }) =>
    checkIns.trainedSince({ member: CheckInMember.parse(member), since }),
  sportListed: (id: string) => sports.isListed(id),
  // A rule counts only 练了 made while its store's and piece's switches were on, by the New York day.
  switches: async () => {
    const on = await switchesOn(scope).states();
    return (id: string, at: Date) => on(id, newYorkDays.format(at));
  },
});
/**
 * A broadcast's gifts, unlocked for the member from the admin who saved it, like `give_unlocks`
 * but quietly: the broadcast itself says the 商店街 has something new, so no unlock notice is
 * told for them.
 */
const giveBroadcastGifts =
  (scope: Database): GiveGifts =>
  async (member, broadcast) => {
    if (broadcast.value.gifts.length === 0) return true;
    if (broadcast.by === null) {
      // Its admin deleted their account: told without the gifts, which nobody can give now.
      log.warn('a broadcast’s gifts have no admin to give them', { broadcast: broadcast.id });
      return true;
    }
    try {
      await createUnlocks(unlockSources(scope)).give(
        { member: UnlockMember.parse(member), items: broadcast.value.gifts },
        UnlockMember.parse(broadcast.by),
      );
      return true;
    } catch (error) {
      log.warn('a broadcast’s gifts not given', { broadcast: broadcast.id, error });
      return false;
    }
  };
// What each member was told (通知, the bell on 动态): pushes and in-app notices, kept forever.
const noticesOn = (scope: Database) =>
  createNotices({
    store: createPostgresNoticeStore(scope),
    broadcasts: createPostgresBroadcastStore(scope),
    clock: () => new Date(),
    giveGifts: giveBroadcastGifts(scope),
  });
const notices = noticesOn(db);
/**
 * Keeps notices after what they tell of happened: a failure is logged, never the event's, even
 * inside an admin tool's transaction.
 */
const tellAfter = async (
  scope: Database,
  { told, what }: { told: readonly NewNotice[]; what: string },
) => {
  try {
    await onItsOwn(scope, () => noticesOn(scope).tell(told));
  } catch (error) {
    log.warn(`${what} not kept in notices`, { error });
  }
};
// What members unlock by training: the unlocks module keeps the rules and who earned what, and
// asks check-ins for the 练了 that count and the sports module which sports exist.
const unlocksOn = (scope: Database) =>
  createUnlocks({
    ...unlockSources(scope),
    unlocked: (member, unlocks) =>
      tellAfter(scope, {
        told: unlocks.map(({ kind, id }) => ({
          member: NoticeMember.parse(member),
          kind: 'unlocked',
          subject: { version: 1, kind, item: id },
        })),
        what: 'an unlock',
      }),
  });
const nudges = createNudges({
  store: createPostgresNudgeStore(db),
  // Who is in which squad is the squads module's to keep: nudges ask it.
  membership: squads,
  timeZoneOf: async (member) => (await members.findProfile(ProfileMember.parse(member)))?.timeZone,
  clock: () => new Date(),
});
/** A coach's name now, as its pushes put it. */
const coachNameOf = async (coach: string): Promise<string> =>
  (await createPostgresCoachCatalog(db).list()).find(({ id }) => id === coach)?.name ?? coach;
const weeklyPlans = createWeeklyPlans({
  store: createPostgresWeeklyPlanStore(db),
  sports,
  calendarOf: memberCalendar(members),
  clock: () => new Date(),
});
// The AI coach runs on OpenAI: without its key the coach never wakes, whatever the settings say.
const coachWakes =
  openaiKey === undefined
    ? undefined
    : createCoachWakes({
        settings: createPostgresCoachSettings(db),
        catalog: createPostgresCoachCatalog(db),
        stores: createPostgresCoachStores(db),
        transaction: postgresCoachTransaction(db),
        agent: createOpenAICoachAgent({ apiKey: openaiKey }),
        squadWeek: coachSquadWeek({
          checkIns,
          members,
          squads,
          sports,
          scenes,
          clock: () => new Date(),
        }),
        // Only the words of members who agreed to the current AI copy reach the model.
        aiConsented: (members) =>
          aiConsent.currentAmong(members.map((member) => ConsentMember.parse(member))),
        hiring: createPostgresCoachHiring(db),
        clock: () => new Date(),
        memberFacts: coachMemberFacts({ checkIns, plans: weeklyPlans, awards, sports }),
        // OpenAI fetches a photo the coach asks to look at from a URL that lasts 10 minutes.
        photoUrls: async (paths) => {
          const parsed = paths.map((path) => PhotoPath.parse(path));
          const urls = await photos.createViewUrls(parsed, 600);
          return parsed.flatMap((path) => urls.get(path)?.href ?? []);
        },
        // The check-in's author finds the reply in 通知, and a line is pushed to them like a
        // teammate's comment (Tracy, 2026-11-03).
        replied: async ({ squad, checkIn, author, coach, text, emoji }) => {
          await tellAfter(db, {
            told: [
              {
                member: NoticeMember.parse(author),
                squad: NoticeSquad.parse(squad),
                kind: 'coachReply',
                subject: {
                  version: 1,
                  checkIn,
                  coach,
                  replied: text !== undefined,
                  emoji: emoji ?? null,
                },
              },
            ],
            what: 'a coach reply',
          });
          if (text === undefined) return;
          await pushCoachLine(
            { push, log },
            {
              checkIn,
              member: author,
              coachName: await coachNameOf(coach),
              text,
              answer: false,
              about: checkIn,
            },
          );
        },
        // So does the member whose reply to the coach it answered.
        answered: async ({ squad, checkIn, comment, commenter, coach, text }) => {
          await tellAfter(db, {
            told: [
              {
                member: NoticeMember.parse(commenter),
                squad: NoticeSquad.parse(squad),
                kind: 'coachReply',
                subject: { version: 1, checkIn, coach, replied: true, emoji: null },
              },
            ],
            what: 'a coach answer',
          });
          await pushCoachLine(
            { push, log },
            {
              checkIn,
              member: commenter,
              coachName: await coachNameOf(coach),
              text,
              answer: true,
              about: comment,
            },
          );
        },
      });
const coachCatalog = createPostgresCoachCatalog(db);
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
  weeklyPlans,
  members,
  squads,
  scenes,
  nudges,
  notices,
  liveEvents,
  coachNames: async () => new Map((await coachCatalog.list()).map(({ id, name }) => [id, name])),
  aiConsent,
  // Data the app shows that lives in the database. Each module keeps its own section.
  catalog: {
    sections: [
      sportsSection(sports),
      scenesSection(scenes),
      switchesSection(switches),
      storesSection(unlocksOn(db)),
      piecesSection(unlocksOn(db)),
      disclaimerDiceSection(createDiceLines({ store: createPostgresDiceLines(db) })),
      artSection(artOn(db)),
    ],
    clock: () => new Date(),
  },
  publicRoutes: {
    proxyHops: config.proxyHops,
    // Someone opening an invite link looks it up a few times at most; guessing a code takes
    // billions of tries, so this only keeps the lookup from being hammered.
    inviteLookups: createMemoryRateLimit({
      limit: 30,
      windowSeconds: 600,
      clock: () => new Date(),
    }),
    // The app reads it about once a launch; a shared address may hold many phones.
    catalogReads: createMemoryRateLimit({
      limit: 300,
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
  coachHiring: createCoachHiring({
    hiring: createPostgresCoachHiring(db),
    catalog: createPostgresCoachCatalog(db),
  }),
  coachActivity,
  weekSummaryWords: () => createPostgresWeekSummaryWords(db).current(),
  weeklyAwards: { awards, clock: () => new Date() },
  unlocks: unlocksOn(db),
  gifts: createCoachGifts({ store: createPostgresGiftStore(db) }),
  log,
  jobs: {
    isScheduler,
    // Each kind of interaction the daily push counts comes from one of these.
    interactions: [checkInInteractions(checkIns), nudgeInteractions(nudges)],
    clock: () => new Date(),
    ...(coachWakes === undefined ? {} : { coach: coachWakes }),
    coachNotes: {
      notes: createCoachNoteDelivery({ store: createPostgresCoachNoteDelivery(db) }),
      noteHour: async () => (await createPostgresCoachSettings(db).current()).noteHour,
      tell: (told) => tellAfter(db, { told, what: 'a coach note' }),
      clock: () => new Date(),
    },
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
      ...disclaimerDiceTools({
        dice: createDiceLines({ store: createPostgresDiceLines(scope) }),
      }),
      ...dailyPushTools({
        settings: createDailyPushSettings({ store: createPostgresDailyPushSettings(scope) }),
      }),
      ...weekSummaryWordTools({
        words: createWeekSummaryWords({ store: createPostgresWeekSummaryWords(scope) }),
      }),
      ...sportTools({ sports: createSports({ store: createPostgresSportStore(scope) }) }),
      ...switchTools({ switches: switchesOn(scope) }),
      ...sceneTools({
        scenes: createScenes({
          store: createPostgresSceneStore(scope),
          switches: () => switchesOn(scope).states(),
        }),
      }),
      ...unlockTools({
        unlocks: unlocksOn(scope),
        gifts: createCoachGifts({ store: createPostgresGiftStore(scope) }),
      }),
      ...broadcastTools({
        broadcasts: noticesOn(scope),
        unlocks: unlocksOn(scope),
        clock: () => new Date(),
      }),
      ...artTools({ art: artOn(scope) }),
      ...coachTools({
        settings: createCoachSettings({ store: createPostgresCoachSettings(scope) }),
        coaches: createCoachCatalog({ store: createPostgresCoachCatalog(scope) }),
        hiring: createCoachHiring({
          hiring: createPostgresCoachHiring(scope),
          catalog: createPostgresCoachCatalog(scope),
        }),
        report: createPostgresCoachReport(scope),
        clock: () => new Date(),
      }),
      ...testPushTools({ push, squads, clock: () => new Date() }),
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
  // Open streams would hold the server open: end them first, and the apps reconnect elsewhere.
  void liveEvents.close();
  server.close(() => {
    void db.destroy();
  });
  // Cloud Run gives an instance 10 seconds after SIGTERM: send the reports still queued.
  void errorReports?.flush(2000);
});
