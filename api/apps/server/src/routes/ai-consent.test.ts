import { randomUUID } from 'node:crypto';

import { MemberId as ConsentMember } from '@wildcard/ai-consent';
import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresReplyStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import {
  createDisclaimerDrafts,
  createPostgresDraftAllowance,
  createPostgresDraftSettings,
} from '@wildcard/disclaimer-drafts';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import {
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import { unusedWeekSummaryWords, unusedWeeklyAwards } from '../test-kit/weekly-awards.js';

// Wired as main.ts wires it: squads and drafts ask the AI consent module itself.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const aiConsent = aiConsentOn(db);
const hasAiConsent = (member: string) => aiConsent.hasCurrent(ConsentMember.parse(member));
const squads = createSquads({
  store: createPostgresSquadStore(db),
  inviteCodes: randomInviteCodes,
  aiConsent: hasAiConsent,
});
const asked: string[] = [];
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  accounts: createSupabaseAccounts({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  }),
  revokeAppleSignIn: undefined,
  publicRoutes: unlimitedPublicRoutes,
  photos,
  checkIns: createCheckIns({
    store: createPostgresCheckInStore(db),
    membership: squads,
    reactions: createPostgresReactionStore(db),
    replies: createPostgresReplyStore(db),
    plans: createPostgresWeeklyPlanStore(db),
    photos,
    calendarOf: () => Promise.resolve(undefined),
    clock: () => new Date(),
  }),
  weeklyPlans: createWeeklyPlans({
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: () => Promise.resolve(undefined),
    clock: () => new Date(),
  }),
  members: createMembers({ store: createPostgresProfileStore(db) }),
  squads,
  aiConsent,
  disclaimerDrafts: createDisclaimerDrafts({
    model: {
      answer: ({ prompt }) => {
        asked.push(prompt);
        return Promise.reject(new Error('Only members who agreed reach the model'));
      },
    },
    settings: createPostgresDraftSettings(db),
    memes: () => Promise.resolve([]),
    allowance: createPostgresDraftAllowance(db),
    aiConsent: hasAiConsent,
    clock: () => new Date(),
    random: () => 0,
  }),
  push: pushOn(db),
  weeklyAwards: unusedWeeklyAwards,
  weekSummaryWords: unusedWeekSummaryWords,
  jobs: noJobs,
  log: createLog(() => undefined),
  admin: adminOn(),
});

async function call(
  ...[method, path, token, body]: [method: string, path: string, token: string, body?: unknown]
) {
  const response = await app.request(path, {
    method,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  const json: unknown = text === '' ? undefined : JSON.parse(text);
  return { status: response.status, body: json };
}

const reasonOf = (body: unknown) => z.object({ reason: z.string() }).parse(body).reason;

const agree = (token: string, copyVersion = 1) =>
  call('PUT', '/me/ai-consent', token, { version: 1, copyVersion });

const SquadBody = z.object({
  id: z.uuid(),
  inviteCode: z.string(),
  members: z.array(z.object({ userId: z.uuid() })),
});
const makeSquad = (token: string) =>
  call('PUT', `/squads/${randomUUID()}`, token, { version: 1, name: '早八跑团' });

describe('GET and PUT /me/ai-consent', () => {
  it('starts with no consent, records one to the current copy, and answers a repeat', async () => {
    const me = await signUp();
    expect(await call('GET', '/me/ai-consent', me.token)).toStrictEqual({
      status: 200,
      body: { version: 1, copyVersion: 1, current: false },
    });

    const agreed = await agree(me.token);
    const Agreed = z.strictObject({
      version: z.literal(1),
      copyVersion: z.literal(1),
      given: z.strictObject({ copyVersion: z.literal(1), givenAt: z.iso.datetime() }),
      current: z.literal(true),
    });
    expect(agreed.status).toBe(200);
    const body = Agreed.parse(agreed.body);
    expect((await agree(me.token)).body).toStrictEqual(body);
    expect((await call('GET', '/me/ai-consent', me.token)).body).toStrictEqual(body);
  });

  it('refuses another version of the copy, and one that can’t be a version', async () => {
    const me = await signUp();
    const outdated = await agree(me.token, 2);
    expect([outdated.status, reasonOf(outdated.body)]).toStrictEqual([
      400,
      'AI_CONSENT_COPY_OUTDATED',
    ]);
    const invalid = await agree(me.token, 0);
    expect([invalid.status, reasonOf(invalid.body)]).toStrictEqual([400, 'REQUEST_INVALID']);
    expect((await call('GET', '/me/ai-consent', me.token)).body).toStrictEqual({
      version: 1,
      copyVersion: 1,
      current: false,
    });
  });

  it('can’t be withdrawn on its own: deleting the account deletes it', async () => {
    const me = await signUp();
    expect((await call('DELETE', '/me/ai-consent', me.token)).status).toBe(404);
  });
});

describe('what needs a current AI consent', () => {
  it('making or joining a squad, but not looking at an invite', async () => {
    const [ann, bo] = [await signUp(), await signUp()];
    const refused = await makeSquad(ann.token);
    expect([refused.status, reasonOf(refused.body)]).toStrictEqual([400, 'AI_CONSENT_REQUIRED']);

    await agree(ann.token);
    const made = await makeSquad(ann.token);
    expect(made.status).toBe(201);
    const { id, inviteCode } = SquadBody.parse(made.body);

    expect((await call('GET', `/squad-invites/${inviteCode}`, bo.token)).status).toBe(200);
    const notYet = await call('POST', `/squad-invites/${inviteCode}/accept`, bo.token);
    expect([notYet.status, reasonOf(notYet.body)]).toStrictEqual([400, 'AI_CONSENT_REQUIRED']);
    await agree(bo.token);
    expect((await call('POST', `/squad-invites/${inviteCode}/accept`, bo.token)).status).toBe(201);
    const squad = SquadBody.parse((await call('GET', `/squads/${id}`, bo.token)).body);
    expect(squad.members.map(({ userId }) => userId)).toStrictEqual([ann.userId, bo.userId]);
  });

  it('AI drafts, whatever the reason, without asking the model', async () => {
    const me = await signUp();
    const draft = (reason: string) =>
      call('POST', '/disclaimer-drafts', me.token, { version: 1, reason, style: 'funny' });
    for (const reason of ['早上没起来', '想自杀']) {
      const refused = await draft(reason);
      expect([refused.status, reasonOf(refused.body)]).toStrictEqual([400, 'AI_CONSENT_REQUIRED']);
    }
    expect(asked).toStrictEqual([]);
  });
});
