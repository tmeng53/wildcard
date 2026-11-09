// @wildcard/app-copy: the app's words put over its String Catalog's, by key, kept in the
// database and served in the public catalog, so a line the app shows changes without a release.

export { createPostgresAppCopy, type AppCopyTables } from './adapters/postgres-app-copy.js';
export {
  AppCopy,
  AppCopyChange,
  applyChange,
  COPY_LIMIT,
  CopyKey,
  CopyWords,
  fillsLike,
  formatArguments,
  MemberId,
} from './domain/app-copy.js';
export type { AppCopyStore } from './ports.js';
export { createAppCopy, type AppCopyAdmin } from './use-cases/app-copy.js';
