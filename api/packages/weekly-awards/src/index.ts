// @wildcard/weekly-awards: each squad's weekly awards (本周颁奖): the titles, award lines and
// moves an AI writes from the week every Sunday evening, its settings, their checks, and their
// tables.

export { createPostgresAwardSettings } from './adapters/postgres-award-settings.js';
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
  type Awards,
  type AwardsState,
  type Failures,
  type MemberAwards,
  type MemberWeek,
  type Title,
  type TopCheckIn,
  type WeekCheckIn,
} from './domain/awards.js';
export { AwardMove } from './domain/moves.js';
export {
  AWARDS_HOUR,
  AWARDS_TIME_ZONE,
  WeekStart,
  awardsTimeOf,
  latestAwardedWeek,
} from './domain/schedule.js';
export { AwardSettings, AwardSettingsChange, ModelName } from './domain/settings.js';
export {
  AwardsModelMissingError,
  AwardsWriterUnavailableError,
  WeekStoryNotReadyError,
} from './errors.js';
export type { AiConsented, AwardSettingsStore, AwardsStore, LanguageModel } from './ports.js';
export { createAwardSettings, type AwardSettingsAdmin } from './use-cases/award-settings.js';
export { createWeeklyAwards, type WeeklyAwards } from './use-cases/weekly-awards.js';
