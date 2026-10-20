import {
  stateOf,
  type AiConsentState,
  type AiConsentTerms,
  type MemberId,
} from '../domain/ai-consent.js';
import type { Clock, ConsentStore } from '../ports.js';
import { giveConsent, type GiveConsentInput } from './ai-consent/give-consent.js';

/**
 * Members' consent to having their words sent to the AI provider: what other modules ask
 * before joining a member to a squad, writing them drafts, or putting them in the weekly awards.
 */
export interface AiConsent {
  /** The member's consent and the terms it must match. */
  find(member: MemberId): Promise<AiConsentState>;
  give(input: GiveConsentInput): Promise<AiConsentState>;
  /** Withdraws the member's consent. Safe to repeat. */
  withdraw(member: MemberId): Promise<void>;
  /** Whether the member has consented to the current terms. */
  hasCurrent(member: MemberId): Promise<boolean>;
  /** Those of `members` who have consented to the current terms. */
  currentAmong(members: readonly MemberId[]): Promise<ReadonlySet<MemberId>>;
}

export function createAiConsent(deps: {
  readonly store: ConsentStore;
  /** What members agree to now: the app's copy version and the provider the server runs. */
  readonly terms: AiConsentTerms;
  readonly clock: Clock;
}): AiConsent {
  return {
    find: async (member) => stateOf(deps.terms, await deps.store.latest(member)),
    give: (input) => giveConsent(deps, input),
    withdraw: (member) => deps.store.withdraw(member, deps.clock()),
    hasCurrent: async (member) => stateOf(deps.terms, await deps.store.latest(member)).current,
    currentAmong: (members) => deps.store.consentingTo(deps.terms, members),
  };
}
