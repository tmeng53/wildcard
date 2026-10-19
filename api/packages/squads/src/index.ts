// @wildcard/squads: squads, who is in each, invite codes, and the rules for joining and leaving.

export { createPostgresSquadStore, type SquadTables } from './adapters/postgres-squad-store.js';
export { randomInviteCodes } from './adapters/random-invite-codes.js';
export { InviteCode, type InviteCodes } from './domain/invite-code.js';
export {
  MemberId,
  SQUAD_MEMBER_LIMIT,
  SQUADS_PER_MEMBER,
  SquadId,
  SquadName,
  type Squad,
  type SquadMember,
} from './domain/squad.js';
export {
  InviteCodeUnknownError,
  SquadFullError,
  SquadIdConflictError,
  SquadLimitReachedError,
  SquadNotJoinedError,
} from './errors.js';
export type { CreateOutcome, JoinOutcome, NewSquad, SquadStore } from './ports.js';
export { createSquads, type Squads } from './use-cases/squads.js';
export type { InvitePreview, PublicInvitePreview } from './use-cases/squads/preview-invite.js';
