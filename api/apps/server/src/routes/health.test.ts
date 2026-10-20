import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createOffSender, createPostgresDeviceStore, createPush } from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { createApp } from '../app.js';
import { readConfig } from '../config.js';
import { createLog } from '../log.js';
import type { Database } from '../ports.js';
import { adminOn, aiConsentOn } from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';

const config = readConfig(process.env);
const notCalled = () => Promise.reject(new Error('no route here verifies tokens or uses photos'));
const photos = {
  createUploadUrl: notCalled,
  exists: notCalled,
  createViewUrls: notCalled,
  deleteAllOf: notCalled,
};
const checkInsOn = (db: Database) =>
  createCheckIns({
    store: createPostgresCheckInStore(db),
    membership: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent: () => Promise.resolve(true),
    }),
    reactions: createPostgresReactionStore(db),
    plans: createPostgresWeeklyPlanStore(db),
    photos,
    calendarOf: () => Promise.resolve(undefined),
    clock: () => new Date(),
  });

async function getHealth(db: Database) {
  const lines: string[] = [];
  const app = createApp({
    db,
    verifyToken: notCalled,
    accounts: { verifySession: notCalled, deleteUser: notCalled, signsInWithApple: notCalled },
    revokeAppleSignIn: undefined,
    publicRoutes: unlimitedPublicRoutes,
    checkIns: checkInsOn(db),
    photos,
    disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
    weeklyPlans: createWeeklyPlans({
      store: createPostgresWeeklyPlanStore(db),
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    members: createMembers({ store: createPostgresProfileStore(db) }),
    push: createPush({ store: createPostgresDeviceStore(db), sender: createOffSender() }),
    squads: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent: () => Promise.resolve(true),
    }),
    aiConsent: aiConsentOn(db),
    log: createLog((line) => lines.push(line)),
    admin: adminOn(),
  });
  try {
    const response = await app.request('/health');
    return {
      status: response.status,
      type: response.headers.get('content-type'),
      body: await response.json(),
      logged: lines.map((line): unknown => JSON.parse(line)),
    };
  } finally {
    await db.destroy();
  }
}

describe('GET /health', () => {
  it('is ok when the database answers', async () => {
    expect(await getHealth(createDatabase(config.databaseUrl))).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: { version: 1, status: 'ok' },
      logged: [],
    });
  });

  it('answers 503 and logs the cause when the database is unreachable', async () => {
    // Nothing listens on port 1: a real refused connection, not a stand-in.
    const result = await getHealth(createDatabase('postgres://postgres@127.0.0.1:1/postgres'));
    expect(result).toMatchObject({
      status: 503,
      type: 'application/problem+json',
      body: {
        version: 1,
        type: 'about:blank',
        title: 'Service Unavailable',
        status: 503,
        detail: 'The service is unavailable right now. Try again shortly.',
        reason: 'DATABASE_UNAVAILABLE',
        errorStatus: 'UNAVAILABLE',
      },
      logged: [
        {
          severity: 'ERROR',
          message: 'request failed',
          method: 'GET',
          path: '/health',
          error: {
            name: 'DatabaseUnavailableError',
            cause: { message: 'connect ECONNREFUSED 127.0.0.1:1' },
          },
        },
      ],
    });
  });
});

describe('an unknown route', () => {
  it('answers 404 as a problem', async () => {
    const db = createDatabase(config.databaseUrl);
    const app = createApp({
      db,
      verifyToken: notCalled,
      accounts: { verifySession: notCalled, deleteUser: notCalled, signsInWithApple: notCalled },
      revokeAppleSignIn: undefined,
      publicRoutes: unlimitedPublicRoutes,
      checkIns: checkInsOn(db),
      photos,
      disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
      weeklyPlans: createWeeklyPlans({
        store: createPostgresWeeklyPlanStore(db),
        calendarOf: () => Promise.resolve(undefined),
        clock: () => new Date(),
      }),
      members: createMembers({ store: createPostgresProfileStore(db) }),
      push: createPush({ store: createPostgresDeviceStore(db), sender: createOffSender() }),
      squads: createSquads({
        store: createPostgresSquadStore(db),
        inviteCodes: randomInviteCodes,
        aiConsent: () => Promise.resolve(true),
      }),
      aiConsent: aiConsentOn(db),
      log: createLog(() => undefined),
      admin: adminOn(),
    });
    const response = await app.request('/nope', { method: 'POST' });
    expect([response.status, await response.json()]).toStrictEqual([
      404,
      {
        version: 1,
        type: 'about:blank',
        title: 'Not Found',
        status: 404,
        detail: 'There is no POST /nope.',
        reason: 'ROUTE_NOT_FOUND',
        errorStatus: 'NOT_FOUND',
      },
    ]);
  });
});
