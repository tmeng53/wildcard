import {
  AdminAction,
  AdminId,
  type LoggedAdminAction,
  type ToolName,
} from '../domain/admin-action.js';
import { NotAnAdminError } from '../errors.js';
import type { AdminStore, Clock } from '../ports.js';

/** The admin list and the log of what admins change. */
export interface Admins {
  /** The member as an admin; throws `NotAnAdminError` when they aren't on the list. */
  requireAdmin(member: string): Promise<AdminId>;
  /** Everyone on the admin list, to tell about something that needs one of them. */
  list(): Promise<AdminId[]>;
  /** Logs one change an admin made with a tool, at the current time. */
  logChange(input: {
    readonly admin: AdminId;
    readonly tool: ToolName;
    readonly arguments: Record<string, unknown>;
  }): Promise<LoggedAdminAction>;
  /** An admin's logged changes, newest first. */
  listLog(query: { readonly admin: AdminId; readonly limit: number }): Promise<LoggedAdminAction[]>;
}

export function createAdmins(deps: { readonly store: AdminStore; readonly clock: Clock }): Admins {
  return {
    requireAdmin: async (member) => {
      if (!(await deps.store.isAdmin(member))) throw new NotAnAdminError();
      return AdminId.parse(member);
    },
    list: () => deps.store.list(),
    logChange: async (input) => {
      const entry = {
        admin: input.admin,
        at: deps.clock(),
        // Parsed, so only JSON reaches the log and its shape is the one stored.
        action: AdminAction.parse({ version: 1, tool: input.tool, arguments: input.arguments }),
      };
      await deps.store.log(entry);
      return entry;
    },
    listLog: (query) => deps.store.listLog(query),
  };
}
