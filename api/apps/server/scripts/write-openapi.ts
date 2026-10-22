// Writes openapi.json from the routes: `pnpm openapi` in api/. src/openapi.test.ts fails when
// the committed file and the routes disagree.
import { writeFileSync } from 'node:fs';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import {
  createOffSender,
  createPostgresDailyPushStore,
  createPostgresDeviceStore,
  createPostgresSettingsStore,
  createPush,
} from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';

import { createDatabase } from '../src/adapters/postgres.js';
import { createApp } from '../src/app.js';
import { createLog } from '../src/log.js';
import { openApiJson } from '../src/openapi.js';

const unused = (): never => {
  throw new Error('Writing the OpenAPI document serves no requests');
};
// Never connected: the pool opens a connection only for a query.
const db = createDatabase('postgres://localhost/unused');
const photos = {
  createUploadUrl: unused,
  exists: unused,
  createViewUrls: unused,
  deleteAllOf: unused,
};
const app = createApp({
  db,
  verifyToken: unused,
  accounts: { verifySession: unused, deleteUser: unused, signsInWithApple: unused },
  revokeAppleSignIn: undefined,
  publicRoutes: { proxyHops: 1, inviteLookups: unused },
  photos,
  checkIns: createCheckIns({
    store: createPostgresCheckInStore(db),
    membership: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
    }),
    reactions: createPostgresReactionStore(db),
    plans: createPostgresWeeklyPlanStore(db),
    photos,
    calendarOf: unused,
    clock: unused,
  }),
  disclaimerDrafts: { write: unused },
  weeklyPlans: createWeeklyPlans({
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: unused,
    clock: unused,
  }),
  members: createMembers({ store: createPostgresProfileStore(db) }),
  push: createPush({
    store: createPostgresDeviceStore(db),
    settings: createPostgresSettingsStore(db),
    daily: createPostgresDailyPushStore(db),
    sender: createOffSender(),
  }),
  squads: createSquads({ store: createPostgresSquadStore(db), inviteCodes: randomInviteCodes }),
  weeklyAwards: {
    awards: {
      give: unused,
      find: unused,
      claimNudge: unused,
      claimWinners: unused,
    },
    clock: unused,
  },
  log: createLog(unused),
  jobs: { token: undefined, interactions: [], clock: unused },
  admin: {
    admins: () => ({ requireAdmin: unused, list: unused, logChange: unused, listLog: unused }),
    tools: () => [],
    publicUrl: new URL('http://localhost:8080'),
    authorizationServer: new URL('http://localhost:54321/auth/v1'),
    consent: {
      signInWithPassword: unused,
      appleSignInUrl: unused,
      exchangeCode: unused,
      request: unused,
      answer: unused,
      signOut: unused,
    },
    passwordSignIn: false,
  },
});
writeFileSync(new URL('../../openapi.json', import.meta.url), openApiJson(app));
await db.destroy();
