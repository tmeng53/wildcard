import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import {
  DisclaimerWriterOffError,
  ModelName,
  createDisclaimerDrafts,
  createPostgresDraftSettings,
} from '@wildcard/disclaimer-drafts';
import {
  createAiUsage,
  createPostgresAiUsageLedger,
  createPostgresAiUsageSettings,
} from '@wildcard/ai-usage';
import type { LanguageModel, ProviderModel } from '@wildcard/language-model';
import { NEW_YORK } from '@wildcard/time-zones';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createAnthropicLanguageModel } from '../adapters/anthropic-language-model.js';
import { byProvider } from '../adapters/language-models.js';
import { createOpenAILanguageModel } from '../adapters/openai-language-model.js';
import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import {
  scenesOn,
  switchesOn,
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  placesOn,
  savedPlacesOn,
  weatherOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { recordedModel, type Fixture, type Provider } from '../test-kit/recorded-model.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import {
  unusedWeeklyAwards,
  unusedUnlocks,
  unusedGifts,
  noRewards,
  unusedCoachHiring,
  unusedCoachActivity,
  unusedCoachLetters,
  ignoredNotices,
  unusedFeedback,
} from '../test-kit/weekly-awards.js';

// The whole server as main.ts wires it: local Supabase's Auth and database (the draft settings
// included), and each provider's adapter answering from recorded responses instead of the
// provider.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());

const settings = createPostgresDraftSettings(db);
const pricedSettings = createPostgresAiUsageSettings(db);

/**
 * The provider's model counted in the AI usage ledger as main.ts counts drafts, the recorded
 * models priced, and everyone's budget for the day `dailyCapMicros`.
 */
function metered(provider: ProviderModel, { dailyCapMicros = 2_000_000_000 } = {}) {
  const price = {
    inputMicrosPerMillion: 100_000,
    cachedInputMicrosPerMillion: 10_000,
    outputMicrosPerMillion: 500_000,
  };
  return createAiUsage({
    settings: {
      current: async () => ({
        ...(await pricedSettings.current()),
        prices: { 'openai/recorded': price, 'anthropic/recorded': price },
        dailyCapMicros,
      }),
    },
    ledger: createPostgresAiUsageLedger(db),
    timeZonesAt: () => Promise.resolve(() => NEW_YORK),
    // Every member here counts to one squad, with no rows of its own: only its budget matters.
    squadOf: () => Promise.resolve('00000000-0000-4000-8000-0000000000aa'),
    clock: () => new Date(),
  }).meter(provider, { feature: 'disclaimer-drafts', capped: true });
}

function appAnswering(
  provider: Provider,
  { answers: fixtures, ...budget }: { answers: [Fixture, ...Fixture[]]; dailyCapMicros?: number },
) {
  const recorded = recordedModel(provider, ...fixtures);
  const options = { baseURL: `http://${provider}.test`, fetch: recorded.fetch };
  const model = metered(
    byProvider(
      provider === 'openai'
        ? { openai: createOpenAILanguageModel({ apiKey: 'sk-openai-test', ...options }) }
        : { anthropic: createAnthropicLanguageModel({ apiKey: 'sk-ant-test', ...options }) },
      () => new DisclaimerWriterOffError(),
    ),
    budget,
  );
  return { ...appWith(model, `${provider}/recorded`), requests: recorded.requests };
}

/** What the ledger counted to a member. */
const countedTo = async (member: string) =>
  db
    .selectFrom('ai_usage')
    .select(['feature', 'squad_id', 'model', 'input_tokens', 'output_tokens', 'cost_micros'])
    .where('member_id', '=', member)
    .execute();

/**
 * The server with this model, the settings as saved but naming `modelName` when given, and what
 * it logs (one parsed entry per line).
 */
function appWith(model: LanguageModel, modelName?: string) {
  const logged: unknown[] = [];
  const photos = createSupabasePhotoStorage({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  });
  const app = createApp({
    db,
    verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
    accounts: createSupabaseAccounts({
      supabaseUrl: config.supabaseUrl,
      secretKey: config.supabaseSecretKey,
    }),
    revokeAppleSignIn: undefined,
    catalog: catalogOn(db),
    publicRoutes: unlimitedPublicRoutes,
    checkIns: createCheckIns({
      sports: createSports({ store: createPostgresSportStore(db) }),
      store: createPostgresCheckInStore(db),
      membership: createSquads({
        store: createPostgresSquadStore(db),
        inviteCodes: randomInviteCodes,
        aiConsent: () => Promise.resolve(true),
      }),
      reactions: createPostgresReactionStore(db),
      comments: createPostgresCommentStore(db),
      plans: createPostgresWeeklyPlanStore(db),
      photos,
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    photos,
    disclaimerDrafts: createDisclaimerDrafts({
      model,
      settings:
        modelName === undefined
          ? settings
          : {
              ...settings,
              current: async () => ({
                ...(await settings.current()),
                model: ModelName.parse(modelName),
              }),
            },
      memes: () => Promise.resolve([]),
      aiConsent: () => Promise.resolve(true),
      random: () => 0,
    }),
    members: createMembers({ store: createPostgresProfileStore(db) }),
    weeklyPlans: createWeeklyPlans({
      sports: createSports({ store: createPostgresSportStore(db) }),
      store: createPostgresWeeklyPlanStore(db),
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    squads: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent: () => Promise.resolve(true),
    }),
    push: pushOn(db),
    aiConsent: aiConsentOn(db),
    nudges: nudgesOn(db),
    ...placesOn(db),
    savedPlaces: savedPlacesOn(db),
    weather: weatherOn(db),
    scenes: scenesOn(db),
    switches: switchesOn(db),
    weeklyAwards: unusedWeeklyAwards,
    unlocks: unusedUnlocks,
    gifts: unusedGifts,
    rewards: noRewards,
    coachHiring: unusedCoachHiring,
    coachActivity: unusedCoachActivity,
    coachLetters: unusedCoachLetters,
    ...ignoredNotices,
    ...unusedFeedback,
    log: createLog((line) => logged.push(JSON.parse(line))),
    jobs: noJobs,
    admin: adminOn(),
  });
  return { app, logged };
}

const Body = z.record(z.string(), z.unknown());

const DEFAULT_REQUEST = { version: 1, reason: '早上没起来', style: 'funny' };

async function ask(
  app: ReturnType<typeof appWith>['app'],
  { token, body = DEFAULT_REQUEST }: { token?: string; body?: unknown },
) {
  const response = await app.request('/disclaimer-drafts', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token === undefined ? {} : { authorization: `Bearer ${token}` }),
    },
    body: JSON.stringify(body),
  });
  return {
    status: response.status,
    type: response.headers.get('content-type'),
    body: Body.parse(await response.json()),
  };
}

describe.each<Provider>(['openai', 'anthropic'])('POST /disclaimer-drafts on %s', (provider) => {
  it('answers three drafts for a signed-in member, counted to them', async () => {
    const { app, requests } = appAnswering(provider, { answers: ['drafts'] });
    const { token, userId } = await signUp();
    const answer = await ask(app, { token });
    expect(answer.status).toBe(200);
    expect(answer.body).toEqual({
      version: 1,
      kind: 'drafts',
      drafts: [
        '闹钟响了三次，我和被子的谈判进入加时赛，目前被子领先。',
        '本人身体已到岗，灵魂仍在床上办理延期手续，预计明早恢复营业。',
        '经核实，早上那句「再眯五分钟」实际时长为两小时，特此通报。',
      ],
    });
    // Only the reason and the style reach the model, with the settings' instructions.
    expect(JSON.stringify(requests)).toContain('原因：早上没起来\\n风格：搞笑');
    expect(JSON.stringify(requests)).toContain('recorded');
    expect(JSON.stringify(requests)).toContain('你在帮一个朋友运动打卡 App 的用户写「请假条」');
    // 812 input tokens at $0.10 and 96 output at $0.50 a million: 81.2 + 48, rounded up.
    expect(await countedTo(userId)).toStrictEqual([
      {
        feature: 'disclaimer-drafts',
        squad_id: null,
        model: `${provider}/recorded`,
        input_tokens: '812',
        output_tokens: '96',
        cost_micros: '130',
      },
    ]);
  });

  it.each<[Fixture, string]>([
    ['self-harm', 'care'],
    ['unsafe', 'declined'],
  ])('answers %s as %s', async (fixture, kind) => {
    const { app } = appAnswering(provider, { answers: [fixture] });
    const { token } = await signUp();
    expect((await ask(app, { token })).body).toEqual({ version: 1, kind });
  });

  it.each<Fixture>(['refusal', 'overloaded'])(
    'answers 503 when %s leaves nothing to show',
    async (fixture) => {
      const { app } = appAnswering(provider, { answers: [fixture] });
      const { token } = await signUp();
      const answer = await ask(app, { token });
      expect(answer.status).toBe(503);
      expect(answer.type).toBe('application/problem+json');
      expect(answer.body.reason).toBe('DISCLAIMER_WRITER_UNAVAILABLE');
    },
  );

  it('answers 503 without an error log when the model’s provider has no key', async () => {
    const { app, logged } = appWith(
      metered(byProvider({}, () => new DisclaimerWriterOffError())),
      `${provider}/recorded`,
    );
    const { token } = await signUp();
    const answer = await ask(app, { token });
    expect([answer.status, answer.body.reason]).toEqual([503, 'DISCLAIMER_WRITER_UNAVAILABLE']);
    expect(logged).toStrictEqual([]);
  });

  it('answers 503 without an error log while drafts are off', async () => {
    const { app, logged } = appWith({
      answer: () => Promise.reject(new DisclaimerWriterOffError()),
    });
    const { token } = await signUp();
    const answer = await ask(app, { token });
    expect(answer).toMatchObject({
      status: 503,
      type: 'application/problem+json',
      body: { reason: 'DISCLAIMER_WRITER_UNAVAILABLE' },
    });
    expect(logged).toStrictEqual([]);
  });

  it('logs an error when the model fails', async () => {
    const { app, logged } = appAnswering(provider, { answers: ['refusal'] });
    const { token } = await signUp();
    expect((await ask(app, { token })).status).toBe(503);
    expect(logged).toMatchObject([
      { severity: 'ERROR', error: { name: 'DisclaimerWriterUnavailableError' } },
    ]);
  });

  it('answers 429 once the day’s AI budget is spent, without asking the model', async () => {
    const { app, requests } = appAnswering(provider, { answers: ['drafts'], dailyCapMicros: 0 });
    const { token, userId } = await signUp();
    const answer = await ask(app, { token });
    expect(answer.status).toBe(429);
    expect(answer.body.reason).toBe('DISCLAIMER_DRAFTS_USED_UP');
    expect(requests).toStrictEqual([]);
    expect(await countedTo(userId)).toStrictEqual([]);
  });

  it('counts the tokens of a refusal too, though it shows nothing', async () => {
    const { app } = appAnswering(provider, { answers: ['refusal'] });
    const { token, userId } = await signUp();
    expect((await ask(app, { token })).status).toBe(503);
    expect(await countedTo(userId)).toHaveLength(1);
  });

  it('refuses an unknown style or an empty reason, and a caller who isn’t signed in', async () => {
    const { app, requests } = appAnswering(provider, { answers: ['drafts'] });
    const { token } = await signUp();
    const style = await ask(app, {
      token,
      body: { version: 1, reason: '下雨了', style: 'poetic' },
    });
    expect([style.status, style.body.reason]).toEqual([400, 'REQUEST_INVALID']);
    const empty = await ask(app, { token, body: { version: 1, reason: ' \n ', style: 'funny' } });
    expect([empty.status, empty.body.reason]).toEqual([400, 'REQUEST_INVALID']);
    const anonymous = await ask(app, {});
    expect([anonymous.status, anonymous.body.reason]).toEqual([401, 'AUTH_TOKEN_MISSING']);
    expect(requests).toHaveLength(0);
  });
});
