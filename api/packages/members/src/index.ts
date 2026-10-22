// @wildcard/members: a signed-in member's own settings (their profile) and its table.

export {
  createPostgresProfileStore,
  type MemberTables,
} from './adapters/postgres-profile-store.js';
export {
  ArtId,
  CATCHPHRASE_MAX_CHARACTERS,
  Catchphrase,
  Character,
  LOOK_MAX_SLOTS,
  Look,
  MemberId,
  NICKNAME_MAX_CHARACTERS,
  Nickname,
  Profile,
  Swatch,
  TimeZone,
  type Squadmate,
} from './domain/profile.js';
export { TimeZoneUnknownError } from './errors.js';
export type { PastLocalHour, ProfileStore } from './ports.js';
export { createMembers, type Members } from './use-cases/members.js';
