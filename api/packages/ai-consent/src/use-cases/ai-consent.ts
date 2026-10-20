import {
  stateOf,
  type AiConsentState,
  type CopyVersion,
  type MemberId,
} from '../domain/ai-consent.js';
import type { Clock, ConsentStore } from '../ports.js';
import { giveConsent, type GiveConsentInput } from './ai-consent/give-consent.js';

/**
 * Members' consent to having their words sent to AI providers: what other modules ask before
 * joining a member to a squad, writing them drafts, or putting them in the weekly awards. It
 * can't be withdrawn on its own; it goes with the account.
 */
export interface AiConsent {
  /** The member's consent and the copy version it must match. */
  find(member: MemberId): Promise<AiConsentState>;
  give(input: GiveConsentInput): Promise<AiConsentState>;
  /** Whether the member has agreed to the current copy. */
  hasCurrent(member: MemberId): Promise<boolean>;
  /** Those of `members` who have agreed to the current copy. */
  currentAmong(members: readonly MemberId[]): Promise<ReadonlySet<MemberId>>;
}

export function createAiConsent(deps: {
  readonly store: ConsentStore;
  /** The version of the copy members agree to now: `AI_CONSENT_COPY_VERSION`. */
  readonly copyVersion: CopyVersion;
  readonly clock: Clock;
}): AiConsent {
  return {
    find: async (member) => stateOf(deps.copyVersion, await deps.store.latest(member)),
    give: (input) => giveConsent(deps, input),
    hasCurrent: async (member) =>
      stateOf(deps.copyVersion, await deps.store.latest(member)).current,
    currentAmong: (members) => deps.store.agreedTo(deps.copyVersion, members),
  };
}
