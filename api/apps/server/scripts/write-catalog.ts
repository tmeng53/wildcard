// Writes the app's bundled copy of the catalog, for its first launch offline, from what local
// Supabase's database serves: `pnpm catalog-snapshot` in api/ after a migration changes a
// section. src/routes/catalog.test.ts fails while the copy is stale.
import { writeFileSync } from 'node:fs';

import { createDiceLines, createPostgresDiceLines } from '@wildcard/disclaimer-drafts';
import { createPostgresSceneStore, createScenes } from '@wildcard/scenes';
import { createPostgresSwitchStore, createSwitches } from '@wildcard/switches';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { z } from 'zod';

import { createDatabase } from '../src/adapters/postgres.js';
import {
  catalog,
  disclaimerDiceSection,
  scenesSection,
  sportsSection,
  switchesSection,
} from '../src/routes/catalog.js';

const db = createDatabase(z.string().parse(process.env.DATABASE_URL));
const app = catalog({
  sections: [
    sportsSection(createSports({ store: createPostgresSportStore(db) })),
    disclaimerDiceSection(createDiceLines({ store: createPostgresDiceLines(db) })),
    scenesSection(
      createScenes({
        store: createPostgresSceneStore(db),
        switches: () => createSwitches({ store: createPostgresSwitchStore(db) }).states(),
      }),
    ),
    switchesSection(createSwitches({ store: createPostgresSwitchStore(db) })),
  ],
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
