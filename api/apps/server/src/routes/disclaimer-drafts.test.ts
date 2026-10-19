import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createDisclaimerDrafts, createPostgresDraftAllowance } from '@wildcard/disclaimer-drafts';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createAnthropicLanguageModel } from '../adapters/anthropic-language-model.js';
import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { config, signUp } from '../test-kit/local-supabase.js';
import { recordedAnthropic, type Fixture } from '../test-kit/recorded-anthropic.js';

// The whole server as main.ts wires it: local Supabase's Auth and database, and the Claude
// adapter answering from recorded responses instead of Anthropic.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());

function appAnswering(...fixtures: [Fixture, ...Fixture[]]) {
  const recorded = recordedAnthropic(...fixtures);
  const photos = createSupabasePhotoStorage({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  });
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
      model: createAnthropicLanguageModel({
        apiKey: 'sk-ant-test',
        baseURL: 'http://anthropic.test',
        fetch: recorded.fetch,
      }),
      memes: () => Promise.resolve([]),
      allowance: createPostgresDraftAllowance(db),
      clock: () => new Date(),
    }),
    members: createMembers({ store: createPostgresProfileStore(db) }),
    weeklyPlans: createWeeklyPlans({
      store: createPostgresWeeklyPlanStore(db),
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    log: createLog(() => undefined),
  });
  return { app, requests: recorded.requests };
}

const Body = z.record(z.string(), z.unknown());

const DEFAULT_REQUEST = { version: 1, reason: '早上没起来', style: 'funny' };

async function ask(
  app: ReturnType<typeof appAnswering>['app'],
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

describe('POST /disclaimer-drafts', () => {
  it('answers three drafts for a signed-in member', async () => {
    const { app, requests } = appAnswering('drafts');
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
    const { app } = appAnswering(fixture);
    const { token } = await signUp();
    expect((await ask(app, { token })).body).toEqual({ version: 1, kind });
  });

  it.each<Fixture>(['body-talk', 'refusal', 'overloaded'])(
    'answers 503 when %s leaves nothing to show',
    async (fixture) => {
      const { app } = appAnswering(fixture);
      const { token } = await signUp();
      const answer = await ask(app, { token });
      expect(answer.status).toBe(503);
      expect(answer.type).toBe('application/problem+json');
      expect(answer.body.reason).toBe('DISCLAIMER_WRITER_UNAVAILABLE');
    },
  );

  it('answers 429 after the day’s 6 batches', async () => {
    const { app } = appAnswering('drafts');
    const { token } = await signUp();
    for (let batch = 0; batch < 6; batch += 1) expect((await ask(app, { token })).status).toBe(200);
    const answer = await ask(app, { token });
    expect(answer.status).toBe(429);
    expect(answer.body.reason).toBe('DISCLAIMER_DRAFTS_USED_UP');
  });

  it('refuses an unknown style or an empty reason, and a caller who isn’t signed in', async () => {
    const { app, requests } = appAnswering('drafts');
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
