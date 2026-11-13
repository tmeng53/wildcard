// @wildcard/squads: squads, who is in each, invite codes, and the rules for joining and leaving.

export { createPostgresSquadStore, type SquadTables } from './adapters/postgres-squad-store.js';
export { randomInviteCodes } from './adapters/random-invite-codes.js';
export { InviteCode, type InviteCodes } from './domain/invite-code.js';
export {
  SUGGESTION_WEEKS,
  overGoal,
  suggestedGoal,
  weeksBefore,
  type GoalSuggestion,
  type GoalWeek,
} from './domain/goal-suggestion.js';
export {
  JOIN_APPROVAL_DEFAULT,
  JOIN_NOTE_MAX_CHARACTERS,
  JoinNote,
  JoinRequestId,
  type JoinRequest,
  type JoinRequestAnswerKind,
} from './domain/join-request.js';
export { FIRST_SCENE, Scene, SceneWeek, type OpenScenes, type ScenePick } from './domain/scene.js';
export {
  MemberId,
  SQUAD_MEMBER_LIMIT,
  SQUADS_PER_MEMBER,
  SquadId,
  SquadName,
  type Squad,
  type SquadMember,
} from './domain/squad.js';
export { zoneAt, zoneFor, type TimeZoneSetting } from './domain/time-zone.js';
export {
  DaysPerMember,
  DEFAULT_DAYS_PER_MEMBER,
  goalFor,
  weekAfter,
  type WeeklyGoalSetting,
} from './domain/weekly-goal.js';
export {
  AiConsentRequiredError,
  InviteCodeUnknownError,
  JoinRequestAnsweredError,
  JoinRequestUnknownError,
  NotScenePickerError,
  NotSquadCaptainError,
  SceneNotOpenError,
  ScenePickedError,
  SceneWeekClosedError,
  SquadFullError,
  SquadIdConflictError,
  SquadLimitReachedError,
  SquadMemberUnknownError,
  SquadNotJoinedError,
  SquadTimeZoneUnknownError,
} from './errors.js';
export type {
  AiConsentCheck,
  AnswerOutcome,
  AskOutcome,
  CreateOutcome,
  CrownHolders,
  JoinOutcome,
  NewSquad,
  SceneWeekAt,
  SquadExit,
  SquadStore,
} from './ports.js';
export {
  createSquadScenes,
  type SceneDeps,
  type SquadScene,
  type SquadScenes,
} from './use-cases/squad-scenes.js';
export { createSquads, type SquadAt, type Squads, type SquadZones } from './use-cases/squads.js';
export type { InvitePreview, PublicInvitePreview } from './use-cases/squads/preview-invite.js';
export type { SquadTimeZone } from './use-cases/squads/time-zone.js';
export type { WeeklyGoal } from './use-cases/squads/weekly-goal.js';
