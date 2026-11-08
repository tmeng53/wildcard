// @wildcard/coach: the AI coach. The coaches a squad can hire (their identity and soul) and the
// settings every coach runs with, both kept in the database and changed through the admin
// tools; each squad hiring and firing its coach; and the coach at work: woken for each check-in and once a day, it reads the squad's
// week, keeps the squad's memory files, posts the 战术板 line, replies and reacts to check-ins, and counts its tokens per squad;
// and when a squad changes coach, the outgoing one leaves the next a letter its members read.
// Coaching is off until it is switched on.

export { createPostgresCoachCatalog } from './adapters/postgres-coach-catalog.js';
export { createPostgresCoachHiring } from './adapters/postgres-coach-hiring.js';
export { createPostgresCoachLetters } from './adapters/postgres-coach-letters.js';
export {
  createPostgresCoachActivity,
  createPostgresCoachNoteDelivery,
  createPostgresCoachReport,
  createPostgresCoachStores,
  postgresCoachTransaction,
} from './adapters/postgres-coach-stores.js';
export {
  createPostgresCoachSettings,
  type CoachTables,
} from './adapters/postgres-coach-settings.js';
export {
  Challenge,
  ChallengeAnswer,
  ChallengeDoneBy,
  DECLINE_REASON_LIMIT,
  DeclineReason,
  type ChallengeCompletion,
  CHALLENGE_AMOUNT_MAX,
  CHALLENGE_LINE_LIMIT,
  CHALLENGE_TITLE_LIMIT,
  CHALLENGE_UNIT_LIMIT,
} from './domain/challenge.js';
export {
  Coach,
  CoachEdit,
  CoachId,
  CoachLook,
  CoachTier,
  CoachWords,
  coachIn,
} from './domain/coach.js';
export {
  CoachModel,
  CoachSettings,
  CoachSettingsChange,
  MemberId,
  SquadId,
} from './domain/settings.js';
export { LETTER_LIMIT, type CoachLetter } from './domain/letter.js';
export { CoachEmoji, REPLY_LIMIT, type CoachAnswer, type CoachReply } from './domain/reply.js';
export type { CheckInKind, SquadWeek, WeekCheckIn, WeekComment } from './domain/squad-week.js';
export type { TokenUsage } from './domain/wake.js';
export type { MemberFacts, PlanDayFacts } from './domain/member-facts.js';
export type {
  AgentRun,
  CoachActivityStore,
  CoachAgent,
  CoachCatalogStore,
  CoachHiringStore,
  CoachLetterStore,
  CoachMemoryStore,
  CoachMemberNoteShown,
  DayChallenge,
  ChallengeAnswered,
  CoachNoteDeliveryStore,
  CoachNoteShown,
  CoachReportStore,
  MemberNote,
  CoachSettingsStore,
  CoachStores,
  CoachMemberFacts,
  CoachMeme,
  CoachGifting,
  CoachMemes,
  CoachWeather,
  CoachOccasions,
  CoachPhotoUrls,
  CoachTool,
  ToolAnswer,
  CoachTransaction,
  SquadCoaching,
  SquadWeekSource,
  UsageTotal,
} from './ports.js';
export {
  CoachAlreadyHiredError,
  CoachFileMemberNotFoundError,
  CoachNotOfferedError,
  CoachCardIdError,
  CoachChallengeDayOverError,
  CoachChallengeDeclinedError,
  CoachNoteNoChallengeError,
  CoachNoteNotFoundError,
  CoachSquadNotFoundError,
  NoCoachHiredError,
} from './errors.js';
export {
  createCoachActivity,
  MAX_CHECK_INS,
  type CoachActivity,
  type SquadCoachActivity,
} from './use-cases/coach-activity.js';
export {
  createCoachNoteDelivery,
  type CoachNoteDelivery,
  type NoteToDeliver,
} from './use-cases/coach-note-delivery.js';
export { createCoachCatalog, type CoachCatalogAdmin } from './use-cases/coach-catalog.js';
export { createCoachHiring, type CoachHiring } from './use-cases/coach-hiring.js';
export {
  createCoachLetters,
  type CoachLettered,
  type CoachLetters,
} from './use-cases/coach-letters.js';
export { createCoachMemory, type CoachMemoryAdmin } from './use-cases/coach-memory.js';
export { CoachFilePath } from './domain/memory.js';
export { createCoachSettings, type CoachSettingsAdmin } from './use-cases/coach-settings.js';
export {
  createCoachWakes,
  type CoachAnswered,
  type CoachReplied,
  type CoachRun,
  type CoachWakes,
  type CoachWakesDependencies,
} from './use-cases/coach-wakes.js';
export {
  CARDS_DAYS,
  CoachCardId,
  CoachCardKind,
  STACK_HOURS,
  cardKey,
  type CoachOwnCard,
} from './domain/cards.js';
