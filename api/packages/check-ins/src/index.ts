// @wildcard/check-ins: daily check-ins (练了, 健康餐, 坦白放纵餐, 今日免责声明), their rules and
// their tables.

export {
  createPostgresCheckInStore,
  type CheckInTables,
} from './adapters/postgres-check-in-store.js';
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
export { SPORTS, SportKey } from './domain/sports.js';
export {
  CheckInDayMismatchError,
  CheckInIdConflictError,
  CheckInInTheFutureError,
  CheckInTooOldError,
  DisclaimerAlreadyPostedError,
  PhotoInUseError,
  PhotoNotUploadedError,
  PhotoNotYoursError,
  SquadNotJoinedError,
} from './errors.js';
export type { TrainingStatus, Week } from './domain/days.js';
export type { CheckInStore, Clock, InsertOutcome, MemberZones, PhotoFiles } from './ports.js';
export { createCheckIns, type CheckIns } from './use-cases/check-ins.js';
export type { SquadMemberToday, SquadToday } from './use-cases/check-ins/squad-today.js';
