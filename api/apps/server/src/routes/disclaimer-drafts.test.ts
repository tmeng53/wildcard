import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresReplyStore,
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
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createAnthropicLanguageModel } from '../adapters/anthropic-language-model.js';
import { createOpenAILanguageModel } from '../adapters/openai-language-model.js';
import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { adminOn, config, noJobs, pushOn, signUp } from '../test-kit/local-supabase.js';
import { recordedModel, type Fixture, type Provider } from '../test-kit/recorded-model.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import { unusedWeeklyAwards } from '../test-kit/weekly-awards.js';

// The whole server as main.ts wires it: local Supabase's Auth and database, and each provider's
// adapter answering from recorded responses instead of the provider.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());

function appAnswering(provider: Provider, ...fixtures: [Fixture, ...Fixture[]]) {
  const recorded = recordedModel(provider, ...fixtures);
  const options = { baseURL: `http://${provider}.test`, fetch: recorded.fetch };
  const model =
    provider === 'openai'
      ? createOpenAILanguageModel({ apiKey: 'sk-openai-test', ...options })
      : createAnthropicLanguageModel({ apiKey: 'sk-ant-test', ...options });
  return { ...appWith(model), requests: recorded.requests };
}

/** The server with this model, and what it logs (one parsed entry per line). */
function appWith(model: LanguageModel) {
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
    publicRoutes: unlimitedPublicRoutes,
    checkIns: createCheckIns({
      store: createPostgresCheckInStore(db),
      membership: createSquads({
        store: createPostgresSquadStore(db),
        inviteCodes: randomInviteCodes,
      }),
      reactions: createPostgresReactionStore(db),
      replies: createPostgresReplyStore(db),
      plans: createPostgresWeeklyPlanStore(db),
      photos,
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    photos,
    disclaimerDrafts: createDisclaimerDrafts({
      model,
      memes: () => Promise.resolve([]),
      allowance: createPostgresDraftAllowance(db),
      clock: () => new Date(),
      random: () => 0,
    }),
    members: createMembers({ store: createPostgresProfileStore(db) }),
    weeklyPlans: createWeeklyPlans({
      store: createPostgresWeeklyPlanStore(db),
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    squads: createSquads({ store: createPostgresSquadStore(db), inviteCodes: randomInviteCodes }),
    push: pushOn(db),
    weeklyAwards: unusedWeeklyAwards,
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
  it('answers three drafts for a signed-in member', async () => {
    const { app, requests } = appAnswering(provider, 'drafts');
    const { token } = await signUp();
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
    // Only the reason and the style reach the model.
    expect(JSON.stringify(requests)).toContain('原因：早上没起来\\n风格：搞笑');
  });

  it.each<[Fixture, string]>([
    ['self-harm', 'care'],
    ['unsafe', 'declined'],
  ])('answers %s as %s', async (fixture, kind) => {
    const { app } = appAnswering(provider, fixture);
    const { token } = await signUp();
    expect((await ask(app, { token })).body).toEqual({ version: 1, kind });
  });

  it.each<Fixture>(['body-talk', 'refusal', 'overloaded'])(
    'answers 503 when %s leaves nothing to show',
    async (fixture) => {
      const { app } = appAnswering(provider, fixture);
      const { token } = await signUp();
      const answer = await ask(app, { token });
      expect(answer.status).toBe(503);
      expect(answer.type).toBe('application/problem+json');
      expect(answer.body.reason).toBe('DISCLAIMER_WRITER_UNAVAILABLE');
    },
  );

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
    const { app, logged } = appAnswering(provider, 'refusal');
    const { token } = await signUp();
    expect((await ask(app, { token })).status).toBe(503);
    expect(logged).toMatchObject([
      { severity: 'ERROR', error: { name: 'DisclaimerWriterUnavailableError' } },
    ]);
  });

  it('answers 429 after the day’s 6 batches', async () => {
    const { app } = appAnswering(provider, 'drafts');
    const { token } = await signUp();
    for (let batch = 0; batch < 6; batch += 1) expect((await ask(app, { token })).status).toBe(200);
    const answer = await ask(app, { token });
    expect(answer.status).toBe(429);
    expect(answer.body.reason).toBe('DISCLAIMER_DRAFTS_USED_UP');
  });

  it('refuses an unknown style or an empty reason, and a caller who isn’t signed in', async () => {
    const { app, requests } = appAnswering(provider, 'drafts');
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
