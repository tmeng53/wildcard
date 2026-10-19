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
    const app = createApp({
      db,
      verifyToken: () => Promise.reject(new Error('unused')),
      checkIns: createCheckIns({
        store: createPostgresCheckInStore(db),
        clock: () => {
          throw new Error('unused');
        },
      }),
      photos: {
        createUploadUrl: () => Promise.reject(new Error('unused')),
        exists: () => Promise.reject(new Error('unused')),
        createViewUrl: () => Promise.reject(new Error('unused')),
      },
      log: createLog(() => undefined),
    });
    const committed = readFileSync(new URL('../openapi.json', import.meta.url), 'utf8');
    expect(committed).toBe(openApiJson(app));
    await db.destroy();
  });
});
