// @wildcard/weekly-awards: each squad's weekly awards (本周颁奖): the titles, award lines and
// moves an AI writes from the week every Sunday evening, their checks, and their table.

export {
  createPostgresAwardsStore,
  type WeeklyAwardTables,
} from './adapters/postgres-awards-store.js';
export {
  CheckInKind,
  MemberId,
  SPEECH_MAX,
  SquadId,
  TITLE_MAX,
  TITLES_MAX,
  topCheckInOf,
  type AwardsState,
  type Failures,
  type MemberAwards,
  type MemberWeek,
  type StoredAwards,
  type Title,
  type TopCheckIn,
  type WeekCheckIn,
} from './domain/awards.js';
export { AWARD_MOVES, AwardMove } from './domain/moves.js';
export {
  AWARDS_HOUR,
  AWARDS_TIME_ZONE,
  WeekStart,
  awardsTimeOf,
  latestAwardedWeek,
} from './domain/schedule.js';
export { AwardsWriterUnavailableError, WeekStoryNotReadyError } from './errors.js';
export type { AwardsStore, LanguageModel } from './ports.js';
export { createWeeklyAwards, type WeeklyAwards } from './use-cases/weekly-awards.js';
