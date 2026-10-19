// @wildcard/check-ins: daily check-ins (练了, 健康餐, 坦白放纵餐, 今日免责声明), teammates'
// reactions on them, their rules and their tables.

export {
  createPostgresCheckInStore,
  type CheckInTables,
} from './adapters/postgres-check-in-store.js';
export { createPostgresReactionStore } from './adapters/postgres-reaction-store.js';
export {
  Audience,
  CheckInDraft,
  CheckInId,
  Disclaimer,
  LocalDay,
  Meal,
  MemberId,
  SquadId,
  Training,
  photosOf,
  storedDisclaimerFields,
  storedMealFields,
  storedTrainingFields,
  type CheckInRecord,
  type Entry,
} from './domain/check-in.js';
export { PhotoPath, PhotoRef, Photos, isOwnPhoto } from './domain/photos.js';
export { DayRange } from './domain/day-range.js';
export { ReactionKind, type Reaction, type ReactOutcome } from './domain/reaction.js';
export { SPORTS, SportKey } from './domain/sports.js';
export {
  CheckInDayMismatchError,
  CheckInIdConflictError,
  CheckInInTheFutureError,
  CheckInNotFoundError,
  CheckInTooOldError,
  DisclaimerAlreadyPostedError,
  OwnCheckInReactionError,
  PhotoInUseError,
  PhotoNotUploadedError,
  PhotoNotYoursError,
  SquadNotJoinedError,
} from './errors.js';
export type { CheckInStore, Clock, InsertOutcome, PhotoFiles, ReactionStore } from './ports.js';
export type { Reacted } from './use-cases/check-ins/react-to-check-in.js';
export { createCheckIns, type CheckIns } from './use-cases/check-ins.js';
