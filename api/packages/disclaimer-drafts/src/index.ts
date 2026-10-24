// @wildcard/disclaimer-drafts: AI drafts for 请假条, their prompt and settings, the checks every
// draft passes, each member's daily allowance, and the dice lines the app rolls without them.

export {
  createPostgresDraftAllowance,
  type DisclaimerDraftTables,
} from './adapters/postgres-draft-allowance.js';
export { createPostgresDiceLines } from './adapters/postgres-dice-lines.js';
export { createPostgresDraftSettings } from './adapters/postgres-draft-settings.js';
export { DiceLine, DiceLineList, DiceLines } from './domain/dice.js';
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
  DiceLinesStore,
  DraftAllowance,
  DraftSettingsStore,
  LanguageModel,
  MemesInUse,
  Random,
  Reservation,
} from './ports.js';
export { createDiceLines, type DiceLinesAdmin } from './use-cases/dice-lines.js';
export { createDisclaimerDrafts, type DisclaimerDrafts } from './use-cases/disclaimer-drafts.js';
export { createDraftSettings, type DraftSettingsAdmin } from './use-cases/draft-settings.js';
