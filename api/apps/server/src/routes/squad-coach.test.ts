import { randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import {
  createCoachHiring,
  createPostgresCoachCatalog,
  createPostgresCoachHiring,
} from '@wildcard/coach';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createMemoryRateLimit } from '../adapters/memory-rate-limit.js';
import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import {
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { unusedWeeklyAwards, unusedWeekSummaryWords } from '../test-kit/weekly-awards.js';
import { catalogOn } from '../test-kit/public-routes.js';

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const members = createMembers({ store: createPostgresProfileStore(db) });
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  accounts: createSupabaseAccounts({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  }),
  revokeAppleSignIn: undefined,
  catalog: catalogOn(db),
  publicRoutes: {
    proxyHops: 1,
    inviteLookups: createMemoryRateLimit({ limit: 3, windowSeconds: 600, clock: () => new Date() }),
    catalogReads: () => ({ allowed: true }),
  },
  photos,
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
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  weeklyPlans: createWeeklyPlans({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  members,
  squads: createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: () => Promise.resolve(true),
  }),
  push: pushOn(db),
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  aiConsent: aiConsentOn(db),
  nudges: nudgesOn(db),
  weeklyAwards: unusedWeeklyAwards,
  weekSummaryWords: unusedWeekSummaryWords,
  coachHiring: createCoachHiring({
    hiring: createPostgresCoachHiring(db),
    catalog: createPostgresCoachCatalog(db),
  }),
  log: createLog(() => undefined),
  jobs: noJobs,
  admin: adminOn(),
});

async function call({
  method,
  path,
  token,
  body,
}: {
  readonly method: string;
  readonly path: string;
  readonly token?: string | undefined;
  readonly body?: unknown;
}) {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  const response = await app.request(path, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  return {
    status: response.status,
    type: response.headers.get('content-type'),
    body: text === '' ? undefined : z.unknown().parse(JSON.parse(text)),
  };
}

const SquadBody = z.object({ id: z.uuid(), inviteCode: z.string() });

/** A squad `captain` made, with `others` in it too. */
async function squadOf(captain: { token: string }, ...others: { token: string }[]) {
  const made = await call({
    method: 'PUT',
    path: `/squads/${randomUUID()}`,
    token: captain.token,
    body: { version: 1, name: '早八跑团' },
  });
  expect(made.status).toBe(201);
  const squad = SquadBody.parse(made.body);
  for (const other of others) {
    const joined = await call({
      method: 'POST',
      path: `/squad-invites/${squad.inviteCode}/accept`,
      token: other.token,
    });
    expect(joined.status).toBe(201);
  }
  return squad.id;
}

const reason = (response: { readonly body?: unknown }) =>
  z.object({ reason: z.string() }).safeParse(response.body).data?.reason;

const card = {
  id: 'xiaohun',
  tier: 'entry',
  name: '小混',
  title: '混混教练',
  catchphrase: '先动起来，证书以后再说',
  background: '体育学院刚毕业，该学的都学了，就是证还没考下来',
  yearsCoaching: 0,
  experience: '热情满格',
  style: '松弛、自嘲、陪着练',
  tags: ['体院应届', '懂行', '松弛', '风趣'],
  pay: '管饭就行',
  look: 'xiaohun',
};

describe('GET /coaches', () => {
  it('lists the coaches a squad can hire with their 简历, never their soul', async () => {
    const me = await signUp();
    const { status, body } = await call({ method: 'GET', path: '/coaches', token: me.token });
    expect([status, body]).toStrictEqual([200, { version: 1, coaches: [card] }]);
    expect(JSON.stringify(body)).not.toContain('你是小混');
    expect((await call({ method: 'GET', path: '/coaches' })).status).toBe(401);
  });
});

describe('/squads/{squadId}/coach', () => {
  it('lets the captain hire, keep and fire the coach, and every member see it', async () => {
    const [captain, mate] = [await signUp(), await signUp()];
    const squad = await squadOf(captain, mate);
    const path = `/squads/${squad}/coach`;

    const none = { version: 1, coach: null, since: null };
    expect(await call({ method: 'GET', path, token: mate.token })).toMatchObject({
      status: 200,
      body: { ...none, canHire: false },
    });

    const hire = { version: 1, coach: 'xiaohun' };
    const before = Date.now();
    const hired = await call({ method: 'PUT', path, token: captain.token, body: hire });
    expect(hired).toMatchObject({ status: 201, body: { version: 1, coach: card, canHire: true } });
    const since = Date.parse(z.object({ since: z.string() }).parse(hired.body).since);
    expect(since).toBeGreaterThanOrEqual(before - 1000);

    // A retry, and what a teammate sees.
    const again = await call({ method: 'PUT', path, token: captain.token, body: hire });
    expect([again.status, again.body]).toStrictEqual([200, hired.body]);
    expect(await call({ method: 'GET', path, token: mate.token })).toMatchObject({
      status: 200,
      body: { coach: card, canHire: false },
    });

    // Only the captain hires and fires.
    const byMate = await call({ method: 'PUT', path, token: mate.token, body: hire });
    expect([byMate.status, reason(byMate)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);
    const firedByMate = await call({ method: 'DELETE', path, token: mate.token });
    expect([firedByMate.status, reason(firedByMate)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);

    const fired = await call({ method: 'DELETE', path, token: captain.token });
    expect([fired.status, fired.body]).toStrictEqual([200, { ...none, canHire: true }]);
    const firedAgain = await call({ method: 'DELETE', path, token: captain.token });
    expect([firedAgain.status, firedAgain.body]).toStrictEqual([200, fired.body]);
  });

  it('refuses a coach that isn’t offered and anyone outside the squad', async () => {
    const [captain, stranger] = [await signUp(), await signUp()];
    const path = `/squads/${await squadOf(captain)}/coach`;
    const nobody = await call({
      method: 'PUT',
      path,
      token: captain.token,
      body: { version: 1, coach: 'nobody' },
    });
    expect([nobody.status, reason(nobody)]).toStrictEqual([400, 'COACH_NOT_OFFERED']);
    for (const method of ['GET', 'PUT', 'DELETE']) {
      const response = await call({
        method,
        path,
        token: stranger.token,
        ...(method === 'PUT' ? { body: { version: 1, coach: 'xiaohun' } } : {}),
      });
      expect([method, response.status, reason(response)]).toStrictEqual([
        method,
        403,
        'SQUAD_NOT_JOINED',
      ]);
    }
  });
});
