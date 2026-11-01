// @wildcard/check-ins: daily check-ins (练了, 健康餐, 坦白放纵餐, 今日请假条), teammates'
// reactions and comments, the weekly plans 本周 counts them against, their rules and their tables.

export {
  createPostgresCheckInStore,
  type CheckInTables,
} from './adapters/postgres-check-in-store.js';
export { createPostgresCommentStore } from './adapters/postgres-comment-store.js';
export { createPostgresReactionStore } from './adapters/postgres-reaction-store.js';
export { createPostgresWeekSummaryWords } from './adapters/postgres-week-summary-words.js';

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
export { PhotoPath, PhotoRef, PhotoSize, Photos, isOwnPhoto } from './domain/photos.js';
export { createPostgresWeeklyPlanStore } from './adapters/postgres-weekly-plan-store.js';
export { DayRange, MyDayRange, Unshared } from './domain/day-range.js';
export {
  CheckInKind,
  DEFAULT_PAGE,
  MAX_PAGE,
  decodeCursor,
  encodeCursor,
  type PostCursor,
} from './domain/post-cursor.js';
export type { CheckInTotals, TopSport } from './domain/totals.js';
export { Emoji, type Reaction, type SaveOutcome } from './domain/reaction.js';
export { CommentId, type Comment } from './domain/comment.js';
export { CommentText } from './domain/text.js';
export {
  DEFAULT_PLAN_DAYS,
  PlanDay,
  PlanDays,
  WEEKS_AHEAD,
  WeekStart,
  type PlanSource,
  type WeeklyPlan,
} from './domain/weekly-plan.js';
export { SportKey } from './domain/sports.js';
export {
  CheckInDayMismatchError,
  CheckInIdConflictError,
  CheckInInTheFutureError,
  CheckInNotFoundError,
  CheckInTooOldError,
  CommentIdConflictError,
  NotYourCommentError,
  OwnCheckInReactionError,
  PhotoInUseError,
  PhotoNotUploadedError,
  PhotoNotYoursError,
  PlanDayStartedError,
  ReplyToNotInSquadError,
  SportNotListedError,
  SquadNotJoinedError,
  TimeZoneNotSetError,
  WeekNotStartedError,
  WeekOverError,
  WeekTooFarAheadError,
} from './errors.js';
export type {
  CheckInStore,
  Clock,
  CommentStore,
  CommentWriteOutcome,
  InsertOutcome,
  MemberCalendar,
  PhotoFiles,
  ReactionStore,
  SportList,
  SquadMembership,
  WeeklyPlanStore,
  WeekSummaryWordsStore,
} from './ports.js';
export type { Reacted } from './use-cases/check-ins/react-to-check-in.js';
export type { CommentInput, Commented } from './use-cases/check-ins/comments.js';
export type { TrainingStatus, Week } from './domain/days.js';
export { createCheckIns, type CheckIns } from './use-cases/check-ins.js';
export type { SquadPost } from './use-cases/check-ins/list-squad-check-ins.js';
export type { MyPostsPage } from './use-cases/check-ins/list-my-posts.js';
export {
  Language,
  WeekSummaryWords,
  WeekSummaryWordsChange,
  winnerText,
} from './domain/week-summary-words.js';
export {
  createWeekSummaryWords,
  type WeekSummaryWordsAdmin,
} from './use-cases/week-summary-words.js';
export type { SquadMemberToday, SquadToday } from './use-cases/check-ins/squad-today.js';
export {
  createWeeklyPlans,
  type PlanTemplate,
  type PlannedWeek,
  type WeeklyPlans,
} from './use-cases/weekly-plans.js';
export {
  FuelGoal,
  FuelGoals,
  FuelSuggestion,
  MAX_FUEL_GOALS,
  OwnFuelGoal,
} from './domain/fuel-goal.js';
export {
  AwardKind,
  StatKind,
  type Award,
  type Stat,
  type WeekSummary,
  type Winner,
} from './domain/week-summary.js';
export type { SquadWeekSummary } from './use-cases/check-ins/week-summary.js';
export type { SquadWeekCheckIns } from './use-cases/check-ins/week-for-awards.js';
