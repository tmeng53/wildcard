import { readFileSync } from 'node:fs';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { z } from 'zod';
import { describe, expect, it } from 'vitest';

import { createApp } from './app.js';
import { createDatabase } from './adapters/postgres.js';
import { createLog } from './log.js';
import { openApiJson } from './openapi.js';
import { noJobs, pushOn } from './test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from './test-kit/public-routes.js';

describe('openapi.json', () => {
  it('matches the routes (run `pnpm openapi` in api/ to rewrite it)', async () => {
    const db = createDatabase('postgres://localhost/unused');
    const photos = {
      createUploadUrl: () => Promise.reject(new Error('unused')),
      exists: () => Promise.reject(new Error('unused')),
      createViewUrls: () => Promise.reject(new Error('unused')),
      deleteAllOf: () => Promise.reject(new Error('unused')),
    };
    const app = createApp({
      db,
      verifyToken: () => Promise.reject(new Error('unused')),
      accounts: {
        verifySession: () => Promise.reject(new Error('unused')),
        deleteUser: () => Promise.reject(new Error('unused')),
        signsInWithApple: () => Promise.reject(new Error('unused')),
      },
      revokeAppleSignIn: undefined,
      publicRoutes: unlimitedPublicRoutes,
      checkIns: createCheckIns({
        store: createPostgresCheckInStore(db),
        reactions: createPostgresReactionStore(db),
        plans: createPostgresWeeklyPlanStore(db),
        photos,
        calendarOf: () => Promise.resolve(undefined),
        clock: () => {
          throw new Error('unused');
        },
      }),
      photos,
      disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
      weeklyPlans: createWeeklyPlans({
        store: createPostgresWeeklyPlanStore(db),
        calendarOf: () => Promise.resolve(undefined),
        clock: () => new Date(),
      }),
      members: createMembers({ store: createPostgresProfileStore(db) }),
      push: pushOn(db),
      squads: createSquads({ store: createPostgresSquadStore(db), inviteCodes: randomInviteCodes }),
      log: createLog(() => undefined),
      jobs: noJobs,
      admin: {
        admins: () => ({
          requireAdmin: () => Promise.reject(new Error('unused')),
          logChange: () => Promise.reject(new Error('unused')),
          listLog: () => Promise.reject(new Error('unused')),
        }),
        tools: () => [],
        publicUrl: new URL('http://localhost:8080'),
        authorizationServer: new URL('http://localhost:54321/auth/v1'),
        consent: {
          signInWithPassword: () => Promise.reject(new Error('unused')),
          appleSignInUrl: () => new URL('http://localhost:54321/auth/v1/authorize'),
          exchangeCode: () => Promise.reject(new Error('unused')),
          request: () => Promise.reject(new Error('unused')),
          answer: () => Promise.reject(new Error('unused')),
          signOut: () => Promise.reject(new Error('unused')),
        },
        passwordSignIn: false,
      },
    });
    const committed = readFileSync(new URL('../openapi.json', import.meta.url), 'utf8');
    expect(committed).toBe(openApiJson(app));
    await db.destroy();
  });

  it('declares 415 on every route that takes a body', () => {
    const document = z
      .object({
        paths: z.record(
          z.string(),
          z.record(
            z.string(),
            z.object({
              requestBody: z.unknown().optional(),
              responses: z.record(z.string(), z.unknown()),
            }),
          ),
        ),
      })
      .parse(JSON.parse(readFileSync(new URL('../openapi.json', import.meta.url), 'utf8')));
    const missing = Object.entries(document.paths).flatMap(([path, operations]) =>
      Object.entries(operations)
        .filter(
          ([, operation]) => operation.requestBody !== undefined && !('415' in operation.responses),
        )
        .map(([method]) => `${method} ${path}`),
    );
    expect(missing).toEqual([]);
  });
});
