// @wildcard/weekly-awards: each squad's weekly awards (本周颁奖): the titles, award lines and
// moves an AI writes from the week every Sunday evening, its settings, their checks, and their
// tables.

export { createPostgresAwardSettings } from './adapters/postgres-award-settings.js';
export { createPostgresWeekStoryStore } from './adapters/postgres-week-story-store.js';
export {
  createPostgresAwardsStore,
  type WeeklyAwardTables,
} from './adapters/postgres-awards-store.js';
export {
  CheckInKind,
  ENDING_HEADLINE_MAX,
  ENDING_LINE_MAX,
  EndingWords,
  MemberId,
  SPEECH_MAX,
  SquadId,
  TITLE_MAX,
  TITLES_MAX,
  boardOf,
  titlesWonOf,
  topCheckInOf,
  wornOf,
  type Awards,
  type AwardsState,
  type BoardTitle,
  type ShownBoardTitle,
  type ShownMemberAwards,
  type ShownTitle,
  type TitleWin,
  type Failures,
  type MemberAwards,
  type MemberWeek,
  type Title,
  type TitlesWon,
  type TopCheckIn,
  type WeekCheckIn,
} from './domain/awards.js';
export {
  Badge,
  BadgeCatalog,
  BadgeColour,
  BadgeGlyph,
  BadgeShape,
  BadgeTone,
  DEFAULT_BADGE,
  shownBadge,
  withSportGlyphs,
  type ShownBadge,
  type SportGlyph,
} from './domain/badges.js';
export type {
  MenuDish,
  PlaceVisit,
  StoryDay,
  StoryMember,
  WeekStory,
} from './domain/week-story.js';
export { AwardMove, CHEER } from './domain/moves.js';
export {
  WeekStart,
  awardsTimeOf,
  lastAwardsTimeOf,
  latestAwardedWeek,
  weekBefore,
  weeksMaybeAwarded,
} from './domain/schedule.js';
export { AwardSettings, AwardSettingsChange, ModelName, offeredMoves } from './domain/settings.js';
export {
  AwardsModelMissingError,
  AwardsWriterUnavailableError,
  TitleNotWonError,
  WeekStoryNotReadyError,
} from './errors.js';
export type { PromptMeme } from './domain/prompt.js';
export type {
  AiConsented,
  AwardSettingsStore,
  AwardsStore,
  WeekStoryStore,
  MemesInUse,
  SportGlyphs,
} from './ports.js';
export { createAwardSettings, type AwardSettingsAdmin } from './use-cases/award-settings.js';
export { createWeeklyAwards, type WeeklyAwards } from './use-cases/weekly-awards.js';
