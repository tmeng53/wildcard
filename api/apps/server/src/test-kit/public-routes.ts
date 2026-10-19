import type { PublicRoutes } from '../routes/squads.js';

/** Public routes with no rate limit, for tests about something else. */
export const unlimitedPublicRoutes: PublicRoutes = {
  proxyHops: 1,
  inviteLookups: () => ({ allowed: true }),
};
