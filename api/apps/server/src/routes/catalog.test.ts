import { readFileSync } from 'node:fs';

import { z } from '@hono/zod-openapi';
import { afterAll, describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { config } from '../test-kit/local-supabase.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import { catalog, type CatalogSection } from './catalog.js';

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());

/** The copy the app ships with, for its first launch offline (`pnpm catalog-snapshot`). */
const BUNDLED = new URL(
  '../../../../../ios/Packages/Backend/Sources/Backend/Resources/catalog.json',
  import.meta.url,
);

describe('GET /public/catalog', () => {
  it('serves the sports list from the database, as the app’s bundled copy has it', async () => {
    const app = catalog({ ...catalogOn(db), publicRoutes: unlimitedPublicRoutes });
    const response = await app.request('/public/catalog');
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toBe('application/json');
    expect(response.headers.get('cache-control')).toBe('no-cache');
    const body: unknown = await response.json();
    expect(body).toMatchObject({
      version: 1,
      sports: {
        picks: { checkInQuick: ['run', 'strength', 'yoga', 'swim', 'spin', 'hike', 'tennis'] },
      },
    });
    // Run `pnpm catalog-snapshot` in api/ after changing the list in a migration.
    expect(body).toStrictEqual(JSON.parse(readFileSync(BUNDLED, 'utf8')));
  });

  it('answers 304 to the ETag the app has, and reads the database again after a minute', async () => {
    let now = new Date('2026-10-23T08:00:00.000Z');
    let words = ['准了'];
    let reads = 0;
    const section: CatalogSection = {
      name: 'replies',
      schema: z.array(z.string()),
      load: () => {
        reads += 1;
        return Promise.resolve(words);
      },
    };
    const app = catalog({
      sections: [section],
      clock: () => now,
      publicRoutes: unlimitedPublicRoutes,
    });
    const get = (etag?: string) =>
      app.request(
        '/public/catalog',
        etag === undefined ? {} : { headers: { 'if-none-match': etag } },
      );

    const first = await get();
    expect(await first.json()).toStrictEqual({ version: 1, replies: ['准了'] });
    const etag = first.headers.get('etag') ?? '';
    expect(etag).toMatch(/^"[\w-]{27}"$/);

    const unchanged = await get(etag);
    expect(unchanged.status).toBe(304);
    expect(unchanged.headers.get('etag')).toBe(etag);
    expect(await unchanged.text()).toBe('');
    expect((await get(`"older", ${etag}`)).status).toBe(304);

    // An edit within the minute isn't read yet; after it, it is, under a new ETag.
    words = ['准了', '不准'];
    now = new Date('2026-10-23T08:00:59.000Z');
    expect((await get(etag)).status).toBe(304);
    expect(reads).toBe(1);
    now = new Date('2026-10-23T08:01:00.000Z');
    const edited = await get(etag);
    expect(edited.status).toBe(200);
    expect(await edited.json()).toStrictEqual({ version: 1, replies: ['准了', '不准'] });
    expect(edited.headers.get('etag')).not.toBe(etag);
    expect(reads).toBe(2);
  });

  it('reads again on the next request when a read fails', async () => {
    let fail = true;
    const section: CatalogSection = {
      name: 'replies',
      schema: z.array(z.string()),
      load: () => (fail ? Promise.reject(new Error('database down')) : Promise.resolve(['准了'])),
    };
    const app = catalog({
      sections: [section],
      clock: () => new Date('2026-10-23T08:00:00.000Z'),
      publicRoutes: unlimitedPublicRoutes,
    });
    expect((await app.request('/public/catalog')).status).toBe(500);
    fail = false;
    expect((await app.request('/public/catalog')).status).toBe(200);
  });
});
