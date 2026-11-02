// @wildcard/coach: the AI coach. The coaches a squad can hire (their identity and soul) and the
// settings every coach runs with, both kept in the database and changed through the admin
// tools; each squad hiring and firing its coach; and the coach at work: woken for each check-in and once a day, it reads the squad's
// week, keeps the squad's memory files, posts the 战术板 line, and counts its tokens per squad.
// Coaching is off until it is switched on.

export { createPostgresCoachCatalog } from './adapters/postgres-coach-catalog.js';
export { createPostgresCoachHiring } from './adapters/postgres-coach-hiring.js';
export {
  createPostgresCoachReport,
  createPostgresCoachStores,
  postgresCoachTransaction,
} from './adapters/postgres-coach-stores.js';
export {
  createPostgresCoachSettings,
  type CoachTables,
} from './adapters/postgres-coach-settings.js';
export { Coach, CoachEdit, CoachId, CoachLook, CoachTier } from './domain/coach.js';
export {
  CoachModel,
  CoachSettings,
  CoachSettingsChange,
  MemberId,
  SquadId,
} from './domain/settings.js';
export type { CheckInKind, SquadWeek, WeekCheckIn } from './domain/squad-week.js';
export type { TokenUsage } from './domain/wake.js';
export type {
  AgentRun,
  CoachAgent,
  CoachCatalogStore,
  CoachHiringStore,
  CoachReportStore,
  CoachSettingsStore,
  CoachStores,
  CoachTool,
  CoachTransaction,
  SquadCoaching,
  SquadWeekSource,
  UsageTotal,
} from './ports.js';
export {
  CoachAlreadyHiredError,
  CoachNotOfferedError,
  CoachSquadNotFoundError,
  NoCoachHiredError,
} from './errors.js';
export { createCoachCatalog, type CoachCatalogAdmin } from './use-cases/coach-catalog.js';
export { createCoachHiring, type CoachHiring } from './use-cases/coach-hiring.js';
export { createCoachSettings, type CoachSettingsAdmin } from './use-cases/coach-settings.js';
export {
  createCoachWakes,
  type CoachRun,
  type CoachWakes,
  type CoachWakesDependencies,
} from './use-cases/coach-wakes.js';
