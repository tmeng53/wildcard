import { createPostgresSportStore, createSports } from '@wildcard/sports';

import type { Database } from '../ports.js';
import { sportsSection, type CatalogSection } from '../routes/catalog.js';
import type { PublicRoutes } from '../routes/squads.js';

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
  sections: [sportsSection(createSports({ store: createPostgresSportStore(db) }))],
  clock,
});
