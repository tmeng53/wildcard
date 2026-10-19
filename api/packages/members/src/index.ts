// @wildcard/members: a signed-in member's own settings (their profile) and its table.

export {
  createPostgresProfileStore,
  type MemberTables,
} from './adapters/postgres-profile-store.js';
export {
  CATCHPHRASE_MAX_CHARACTERS,
  Catchphrase,
  MemberId,
  Profile,
  TimeZone,
} from './domain/profile.js';
export { TimeZoneUnknownError } from './errors.js';
export type { ProfileStore } from './ports.js';
export { createMembers, type Members } from './use-cases/members.js';
