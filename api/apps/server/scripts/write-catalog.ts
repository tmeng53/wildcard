// Writes the app's bundled copy of the catalog, for its first launch offline, from what local
// Supabase's database serves: `pnpm catalog-snapshot` in api/ after a migration changes the
// list. src/routes/catalog.test.ts fails while the copy is stale.
import { writeFileSync } from 'node:fs';

import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { z } from 'zod';

import { createDatabase } from '../src/adapters/postgres.js';
import { catalog, sportsSection } from '../src/routes/catalog.js';

const db = createDatabase(z.string().parse(process.env.DATABASE_URL));
const app = catalog({
  sections: [sportsSection(createSports({ store: createPostgresSportStore(db) }))],
  clock: () => new Date(),
  publicRoutes: {
    proxyHops: 1,
    inviteLookups: () => ({ allowed: true }),
    catalogReads: () => ({ allowed: true }),
  },
});
const response = await app.request('/public/catalog');
const body: unknown = await response.json();
writeFileSync(
  new URL(
    '../../../../../ios/Packages/Backend/Sources/Backend/Resources/catalog.json',
    import.meta.url,
  ),
  `${JSON.stringify(body, null, 2)}\n`,
);
await db.destroy();
