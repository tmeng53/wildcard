// Writes openapi.json from the routes: `pnpm openapi` in api/. src/openapi.test.ts fails when
// the committed file and the routes disagree.
import { writeFileSync } from 'node:fs';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresQuickReactions,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createQuickReactions,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createAppCopy, createPostgresAppCopy } from '@wildcard/app-copy';
import { createDiceLines, createPostgresDiceLines } from '@wildcard/disclaimer-drafts';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import {
  createOffSender,
  createPostgresDailyPushSettings,
  createPostgresDailyPushStore,
  createPostgresDeviceStore,
  createPostgresSettingsStore,
  createPush,
} from '@wildcard/push';
import { createPostgresSceneStore, createScenes } from '@wildcard/scenes';
import {
  createMinimumBuilds,
  createPostgresMinimumBuild,
  createPostgresSwitchStore,
  createSwitches,
} from '@wildcard/switches';
import { createPostgresUnlockStore } from '@wildcard/unlocks';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';

import { createDatabase } from '../src/adapters/postgres.js';
import { createApp } from '../src/app.js';
import { createLog } from '../src/log.js';
import { openApiJson } from '../src/openapi.js';
import {
  artSection,
  appBuildSection,
  appCopySection,
  disclaimerDiceSection,
  reactionsSection,
  scenesSection,
  sportsSection,
  switchesSection,
  storesSection,
  piecesSection,
} from '../src/routes/catalog.js';

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
  delete: unused,
};
const app = createApp({
  db,
  verifyToken: unused,
  accounts: {
    verifySession: unused,
    deleteUser: unused,
    signsInWithApple: unused,
    createUser: unused,
    handOff: unused,
  },
  revokeAppleSignIn: undefined,
  catalog: {
    sections: [
      sportsSection(createSports({ store: createPostgresSportStore(db) })),
      disclaimerDiceSection(createDiceLines({ store: createPostgresDiceLines(db) })),
      appCopySection(createAppCopy({ store: createPostgresAppCopy(db) })),
      scenesSection(
        createScenes({
          store: createPostgresSceneStore(db),
          switches: () => createSwitches({ store: createPostgresSwitchStore(db) }).states(),
        }),
      ),
      switchesSection(createSwitches({ store: createPostgresSwitchStore(db) })),
      storesSection(createPostgresUnlockStore(db)),
      piecesSection(createPostgresUnlockStore(db)),
      appBuildSection(createMinimumBuilds({ store: createPostgresMinimumBuild(db) })),
      reactionsSection(createQuickReactions({ store: createPostgresQuickReactions(db) })),
      artSection({ manifest: unused }),
    ],
    clock: unused,
  },
  publicRoutes: { proxyHops: 1, inviteLookups: unused, catalogReads: unused },
  photos,
  checkIns: createCheckIns({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresCheckInStore(db),
    membership: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent: unused,
    }),
    reactions: createPostgresReactionStore(db),
    comments: createPostgresCommentStore(db),
    plans: createPostgresWeeklyPlanStore(db),
    photos,
    calendarOf: unused,
    clock: unused,
  }),
  nudges: { send: unused, received: unused, inSquad: unused },
  placeRatings: { rate: unused, of: unused, ofAll: unused },
  savedPlaces: { list: unused, save: unused, remove: unused },
  weather: { savePlace: unused, forgetPlace: unused, dayFor: unused },
  feedback: { send: unused, toFile: unused, filed: unused },
  issues: undefined,
  notices: { tell: unused, page: unused, markSeen: unused },
  switches: { list: unused, statesFor: unused },
  coachNames: unused,
  liveEvents: { subscribe: unused, close: unused },
  disclaimerDrafts: { write: unused },
  weeklyPlans: createWeeklyPlans({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: unused,
    clock: unused,
  }),
  members: createMembers({ store: createPostgresProfileStore(db) }),
  push: createPush({
    store: createPostgresDeviceStore(db),
    settings: createPostgresSettingsStore(db),
    daily: createPostgresDailyPushStore(db),
    dailySettings: createPostgresDailyPushSettings(db),
    sender: createOffSender(),
  }),
  squads: createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: unused,
  }),
  aiConsent: {
    find: unused,
    give: unused,
    hasCurrent: unused,
    currentAmong: unused,
  },
  coachHiring: { hire: unused, fire: unused, change: unused, current: unused, offered: unused },
  coachActivity: {
    squad: unused,
    answerChallenge: unused,
    challenge: unused,
    completeChallenge: unused,
    cards: unused,
    markSeen: unused,
    spoke: unused,
  },
  coachLetters: { write: unused },
  scenes: createScenes({
    store: createPostgresSceneStore(db),
    switches: () => createSwitches({ store: createPostgresSwitchStore(db) }).states(),
  }),
  weeklyAwards: {
    awards: {
      give: unused,
      find: unused,
      claimNudge: unused,
      claimReadyPush: unused,
      titlesWon: unused,
      boards: unused,
      shownTitles: unused,
      story: unused,
      freezeStory: unused,
      storyWeeks: unused,
      storiesWaiting: unused,
    },
    clock: unused,
  },
  unlocks: { of: unused, standing: unused, claimsOf: unused, claim: unused, keepWorn: unused },
  gifts: { of: unused, open: unused },
  rewards: { badgesOf: unused, teamPiecesOf: unused },
  log: createLog(unused),
  jobs: {
    isScheduler: undefined,
    interactions: [],
    clock: unused,
    suggestGoal: unused,
    coachNotes: {
      notes: { waiting: unused, delivered: unused },
      noteHour: unused,
      tell: unused,
      clock: unused,
    },
  },
  admin: {
    admins: () => ({
      requireAdmin: unused,
      isAdmin: unused,
      list: unused,
      logChange: unused,
      listLog: unused,
      demoOwner: unused,
      isDemoAccount: unused,
      demoAccounts: unused,
      addDemoAccount: unused,
      requireDemoAccount: unused,
    }),
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
