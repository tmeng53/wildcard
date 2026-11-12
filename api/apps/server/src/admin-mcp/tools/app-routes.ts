import { APP_ROUTES, APP_SCHEME } from '@wildcard/app-routes';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// Where a button may go: every place in the app by its address. A broadcast's button and any
// later card or push take one of these, so where a button goes changes without a release.

/** `list_app_routes`: every place in the app a button may open. */
export function listAppRoutes() {
  return adminTool({
    name: 'list_app_routes',
    title: 'List the places in the app',
    description:
      'Shows every place in the app a button may open, by its address (such as store/powder or ' +
      'coach; wildcard:// before it is optional): the pattern, what it opens and a sample. A ' +
      'build that does not know an address shows no button for it.',
    changes: false,
    input: z.strictObject({}),
    run: () => Promise.resolve({ version: 1, scheme: APP_SCHEME, routes: APP_ROUTES }),
  });
}

export const appRouteTools = () => [listAppRoutes()];
