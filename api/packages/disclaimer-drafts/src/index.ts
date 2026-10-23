// @wildcard/disclaimer-drafts: AI drafts for 请假条, their prompt, the checks every draft
// passes, and each member's daily allowance.

export {
  createPostgresDraftAllowance,
  type DisclaimerDraftTables,
} from './adapters/postgres-draft-allowance.js';
export { DraftReason, MemberId, type PromptMeme } from './domain/draft-request.js';
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
  LanguageModel,
  MemesInUse,
  Random,
  Reservation,
} from './ports.js';
export { createDisclaimerDrafts, type DisclaimerDrafts } from './use-cases/disclaimer-drafts.js';
