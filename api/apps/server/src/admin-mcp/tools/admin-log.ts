import type { Admins } from '@wildcard/admins';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

/** `list_admin_log`: the caller's own logged changes, newest first. */
export function listAdminLog(deps: { readonly admins: Admins }) {
  return adminTool({
    name: 'list_admin_log',
    title: 'List my admin changes',
    description:
      'Lists the changes you made with the admin tools, newest first: when, which tool, and ' +
      'the arguments it was called with.',
    changes: false,
    input: z.strictObject({
      limit: z.int().min(1).max(200).default(50).describe('How many changes to list, at most.'),
    }),
    run: async ({ limit }, { admin }) => {
      const log = await deps.admins.listLog({ admin, limit });
      return {
        version: 1,
        changes: log.map(({ at, action }) => ({
          at: at.toISOString(),
          tool: action.tool,
          arguments: action.arguments,
        })),
      };
    },
  });
}
