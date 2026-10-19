// @wildcard/check-ins: daily check-ins (练了, 健康餐, 坦白放纵餐, 今日免责声明), the weekly
// plans 本周 counts them against, their rules and their tables.

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
export { createPostgresWeeklyPlanStore } from './adapters/postgres-weekly-plan-store.js';
export { DayRange } from './domain/day-range.js';
export {
  DEFAULT_PLAN_DAYS,
  PlanDay,
  PlanDays,
  WEEKS_AHEAD,
  WeekStart,
  type PlanSource,
  type WeeklyPlan,
} from './domain/weekly-plan.js';
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
  PlanDayStartedError,
  RestDaysFixedError,
  SquadNotJoinedError,
  TimeZoneNotSetError,
  WeekOverError,
  WeekTooFarAheadError,
} from './errors.js';
export type {
  CheckInStore,
  Clock,
  InsertOutcome,
  MemberCalendar,
  PhotoFiles,
  WeeklyPlanStore,
} from './ports.js';
export { createCheckIns, type CheckIns } from './use-cases/check-ins.js';
export { createWeeklyPlans, type WeeklyPlans } from './use-cases/weekly-plans.js';
