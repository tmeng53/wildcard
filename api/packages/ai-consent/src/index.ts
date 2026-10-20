// @wildcard/ai-consent: members' consent to having their words sent to AI providers, the copy
// version it must match, and its table.

export {
  createPostgresConsentStore,
  type AiConsentTables,
} from './adapters/postgres-consent-store.js';
export {
  AI_CONSENT_COPY_VERSION,
  CopyVersion,
  MemberId,
  type AiConsentState,
  type GivenConsent,
} from './domain/ai-consent.js';
export { AiConsentCopyOutdatedError } from './errors.js';
export type { Clock, ConsentStore } from './ports.js';
export { createAiConsent, type AiConsent } from './use-cases/ai-consent.js';
