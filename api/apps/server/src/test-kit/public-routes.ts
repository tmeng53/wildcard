import { createPostgresArtStore } from '@wildcard/art';
import { createDiceLines, createPostgresDiceLines } from '@wildcard/disclaimer-drafts';
import { createPostgresSceneStore, createScenes } from '@wildcard/scenes';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import {
  createMinimumBuilds,
  createPostgresMinimumBuild,
  createPostgresSwitchStore,
  createSwitches,
} from '@wildcard/switches';
import { createPostgresQuickReactions, createQuickReactions } from '@wildcard/check-ins';
import { createPostgresUnlockStore } from '@wildcard/unlocks';

import type { Database } from '../ports.js';
import {
  artSection,
  appBuildSection,
  disclaimerDiceSection,
  reactionsSection,
  scenesSection,
  sportsSection,
  switchesSection,
  storesSection,
  piecesSection,
  type CatalogSection,
} from '../routes/catalog.js';
import type { PublicRoutes } from '../routes/squads.js';
import { config } from './local-supabase.js';

/** Public routes with no rate limit, for tests about something else. */
export const unlimitedPublicRoutes: PublicRoutes = {
  proxyHops: 1,
  inviteLookups: () => ({ allowed: true }),
  catalogReads: () => ({ allowed: true }),
};

/** The catalog's sections as `main.ts` lists them, on this database, read afresh each time. */
export const catalogOn = (
  db: Database,
  clock: () => Date = () => new Date(),
): { readonly sections: readonly CatalogSection[]; readonly clock: () => Date } => ({
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
    storesSection(createPostgresUnlockStore(db)),
    piecesSection(createPostgresUnlockStore(db)),
    appBuildSection(createMinimumBuilds({ store: createPostgresMinimumBuild(db) })),
    reactionsSection(createQuickReactions({ store: createPostgresQuickReactions(db) })),
    // The art as main.ts serves it: the database's list, downloaded from local Storage.
    artSection({
      manifest: async () => ({
        ...(await createPostgresArtStore(db).manifest()),
        baseUrl: new URL(`${config.supabaseUrl}/storage/v1/object/public/art/`),
      }),
    }),
  ],
  clock,
});
