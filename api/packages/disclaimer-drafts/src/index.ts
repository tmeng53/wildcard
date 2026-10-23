// @wildcard/disclaimer-drafts: AI drafts for 请假条, their prompt and settings, the checks every
// draft passes, and each member's daily allowance.

export {
  createPostgresDraftAllowance,
  type DisclaimerDraftTables,
} from './adapters/postgres-draft-allowance.js';
export { createPostgresDraftSettings } from './adapters/postgres-draft-settings.js';
export { DraftReason, MemberId, type PromptMeme } from './domain/draft-request.js';
export { DraftSettings, DraftSettingsChange, ModelName } from './domain/settings.js';
export type { DraftsOutcome } from './domain/drafts.js';
export {
  AiConsentRequiredError,
  DisclaimerDraftsUsedUpError,
  DisclaimerWriterOffError,
  DisclaimerWriterUnavailableError,
} from './errors.js';
export type {
  AiConsentCheck,
  Clock,
  DraftAllowance,
  DraftSettingsStore,
  LanguageModel,
  MemesInUse,
  Random,
  Reservation,
} from './ports.js';
export { createDisclaimerDrafts, type DisclaimerDrafts } from './use-cases/disclaimer-drafts.js';
export { createDraftSettings, type DraftSettingsAdmin } from './use-cases/draft-settings.js';
