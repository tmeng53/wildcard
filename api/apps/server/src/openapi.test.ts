import { readFileSync } from 'node:fs';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { describe, expect, it } from 'vitest';

import { createApp } from './app.js';
import { createDatabase } from './adapters/postgres.js';
import { createLog } from './log.js';
import { openApiJson } from './openapi.js';

describe('openapi.json', () => {
  it('matches the routes (run `pnpm openapi` in api/ to rewrite it)', async () => {
    const db = createDatabase('postgres://localhost/unused');
    const photos = {
      createUploadUrl: () => Promise.reject(new Error('unused')),
      exists: () => Promise.reject(new Error('unused')),
      createViewUrls: () => Promise.reject(new Error('unused')),
    };
    const app = createApp({
      db,
      verifyToken: () => Promise.reject(new Error('unused')),
      checkIns: createCheckIns({
        store: createPostgresCheckInStore(db),
        photos,
        clock: () => {
          throw new Error('unused');
        },
      }),
      photos,
      weeklyPlans: createWeeklyPlans({
        store: createPostgresWeeklyPlanStore(db),
        calendarOf: () => Promise.resolve(undefined),
        clock: () => new Date(),
      }),
      members: createMembers({ store: createPostgresProfileStore(db) }),
      squads: createSquads({ store: createPostgresSquadStore(db), inviteCodes: randomInviteCodes }),
      log: createLog(() => undefined),
    });
    const committed = readFileSync(new URL('../openapi.json', import.meta.url), 'utf8');
    expect(committed).toBe(openApiJson(app));
    await db.destroy();
  });
});
