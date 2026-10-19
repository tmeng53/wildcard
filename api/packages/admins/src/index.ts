// @wildcard/admins: who may use the admin tools, and the log of every change they make.

export { createPostgresAdminStore, type AdminTables } from './adapters/postgres-admin-store.js';
export { AdminAction, AdminId, ToolName, type LoggedAdminAction } from './domain/admin-action.js';
export { NotAnAdminError } from './errors.js';
export type { AdminStore, Clock } from './ports.js';
export { createAdmins, type Admins } from './use-cases/admins.js';
