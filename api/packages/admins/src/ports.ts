import type { AdminId, LoggedAdminAction } from './domain/admin-action.js';

/** Where the admin list and the log of their changes are kept. */
export interface AdminStore {
  /** Whether this member is on the admin list. */
  isAdmin(member: string): Promise<boolean>;
  /** Everyone on the admin list. */
  list(): Promise<AdminId[]>;
  /** Adds one change to the log. */
  log(entry: LoggedAdminAction): Promise<void>;
  /** An admin's logged changes, newest first, at most `limit`. */
  listLog(query: { readonly admin: AdminId; readonly limit: number }): Promise<LoggedAdminAction[]>;
}

/** The current time. */
export type Clock = () => Date;
