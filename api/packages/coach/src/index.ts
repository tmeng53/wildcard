// @wildcard/coach: the AI coach. For now, the coaches a squad can have (their identity and
// soul) and the settings every coach runs with, both kept in the database and changed through
// the admin tools. Coaching is off until it is switched on.

export { createPostgresCoachCatalog } from './adapters/postgres-coach-catalog.js';
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
export type { CoachCatalogStore, CoachSettingsStore } from './ports.js';
export { createCoachCatalog, type CoachCatalogAdmin } from './use-cases/coach-catalog.js';
export { createCoachSettings, type CoachSettingsAdmin } from './use-cases/coach-settings.js';
