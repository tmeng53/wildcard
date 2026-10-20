import {
  sameTerms,
  stateOf,
  type AiConsentState,
  type AiConsentTerms,
  type MemberId,
} from '../../domain/ai-consent.js';
import { AiConsentTermsOutdatedError } from '../../errors.js';
import type { Clock, ConsentStore } from '../../ports.js';

export interface GiveConsentInput {
  readonly member: MemberId;
  /** The terms the app showed the member, which must be the current ones. */
  readonly terms: AiConsentTerms;
}

/**
 * Records the member's consent to the current terms. Safe to repeat: a member who consented to
 * them already keeps that consent and when they gave it. Throws `AiConsentTermsOutdatedError`
 * for any other terms.
 */
export async function giveConsent(
  deps: { readonly store: ConsentStore; readonly terms: AiConsentTerms; readonly clock: Clock },
  { member, terms }: GiveConsentInput,
): Promise<AiConsentState> {
  if (!sameTerms(terms, deps.terms)) throw new AiConsentTermsOutdatedError();
  const latest = await deps.store.latest(member);
  if (latest !== undefined && sameTerms(latest.terms, deps.terms)) {
    return stateOf(deps.terms, latest);
  }
  const given = { terms: deps.terms, givenAt: deps.clock() };
  await deps.store.give(member, given);
  return stateOf(deps.terms, given);
}
