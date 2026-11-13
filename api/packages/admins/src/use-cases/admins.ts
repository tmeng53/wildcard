import {
  AdminAction,
  AdminId,
  type LoggedAdminAction,
  type ToolName,
} from '../domain/admin-action.js';
import { DemoAccountNotFoundError, NotAnAdminError } from '../errors.js';
import type { AdminStore, Clock } from '../ports.js';

/** The admin list and the log of what admins change. */
export interface Admins {
  /** The member as an admin; throws `NotAnAdminError` when they aren't on the list. */
  requireAdmin(member: string): Promise<AdminId>;
  /** Whether the member is on the admin list, for what only admins see in the app. */
  isAdmin(member: string): Promise<boolean>;
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
  /**
   * The admin whose demo accounts the member may switch between: the member themselves when
   * they are an admin, the admin who made it when they are signed in on a demo account. Throws
   * `NotAnAdminError` for anyone else.
   */
  demoOwner(member: string): Promise<AdminId>;
  /** Whether the member is a demo account an admin made. */
  isDemoAccount(member: string): Promise<boolean>;
  /** The admin's demo accounts, the oldest first. */
  demoAccounts(admin: AdminId): Promise<string[]>;
  /** Records a demo account the admin just made, at the current time. */
  addDemoAccount(admin: AdminId, member: string): Promise<void>;
  /** The member, when it is one of the admin's demo accounts; else `DemoAccountNotFoundError`. */
  requireDemoAccount(admin: AdminId, member: string): Promise<string>;
}

export function createAdmins(deps: { readonly store: AdminStore; readonly clock: Clock }): Admins {
  return {
    requireAdmin: async (member) => {
      if (!(await deps.store.isAdmin(member))) throw new NotAnAdminError();
      return AdminId.parse(member);
    },
    isAdmin: (member) => deps.store.isAdmin(member),
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
    demoOwner: async (member) => {
      if (await deps.store.isAdmin(member)) return AdminId.parse(member);
      const owner = await deps.store.demoAccountOwner(member);
      if (owner === undefined) throw new NotAnAdminError();
      return owner;
    },
    isDemoAccount: async (member) => (await deps.store.demoAccountOwner(member)) !== undefined,
    demoAccounts: (admin) => deps.store.demoAccounts(admin),
    addDemoAccount: (admin, member) =>
      deps.store.addDemoAccount({ admin, member, at: deps.clock() }),
    requireDemoAccount: async (admin, member) => {
      if ((await deps.store.demoAccountOwner(member)) !== admin)
        throw new DemoAccountNotFoundError();
      return member;
    },
  };
}
