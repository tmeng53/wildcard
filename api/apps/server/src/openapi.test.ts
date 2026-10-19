import { readFileSync } from 'node:fs';

import { createCheckIns, createPostgresCheckInStore } from '@wildcard/check-ins';
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
      log: createLog(() => undefined),
      admin: {
        admins: {
          requireAdmin: () => Promise.reject(new Error('unused')),
          logChange: () => Promise.reject(new Error('unused')),
          listLog: () => Promise.reject(new Error('unused')),
        },
        tools: [],
        publicUrl: new URL('http://localhost:8080'),
        authorizationServer: new URL('http://localhost:54321/auth/v1'),
      },
    });
    const committed = readFileSync(new URL('../openapi.json', import.meta.url), 'utf8');
    expect(committed).toBe(openApiJson(app));
    await db.destroy();
  });
});
