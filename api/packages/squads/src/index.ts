// @wildcard/squads: squads, who is in each, invite codes, and the rules for joining and leaving.

export { createPostgresSquadStore, type SquadTables } from './adapters/postgres-squad-store.js';
export { randomInviteCodes } from './adapters/random-invite-codes.js';
export { InviteCode, type InviteCodes } from './domain/invite-code.js';
export { FIRST_SCENE, Scene, SceneWeek, type ScenePick } from './domain/scene.js';
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
  AiConsentRequiredError,
  InviteCodeUnknownError,
  NotScenePickerError,
  NotSquadCaptainError,
  ScenePickedError,
  SceneWeekClosedError,
  SquadFullError,
  SquadIdConflictError,
  SquadLimitReachedError,
  SquadMemberUnknownError,
  SquadNotJoinedError,
} from './errors.js';
export type {
  AiConsentCheck,
  CreateOutcome,
  CrownHolders,
  JoinOutcome,
  NewSquad,
  SceneWeekAt,
  SquadStore,
} from './ports.js';
export {
  createSquadScenes,
  type SceneDeps,
  type SquadScene,
  type SquadScenes,
} from './use-cases/squad-scenes.js';
export { createSquads, type Squads } from './use-cases/squads.js';
export type { InvitePreview, PublicInvitePreview } from './use-cases/squads/preview-invite.js';
