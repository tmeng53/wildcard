import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/** The third-party AI the member's words are sent to: the one the server runs. */
export const AiProvider = z.enum(['openai', 'anthropic']);
export type AiProvider = z.infer<typeof AiProvider>;

/**
 * The version of the consent copy the app shows. The copy itself lives in the app's String
 * Catalog; bump this with any change to what it says, and every member is asked again.
 */
export const AI_CONSENT_COPY_VERSION = 1;

/**
 * What a member agrees to: the copy they were shown, at its version, naming the provider. A
 * new copy version or another provider is new terms, so a consent to the old ones no longer
 * counts.
 */
export const AiConsentTerms = z.strictObject({
  copyVersion: z.int().min(1),
  provider: AiProvider,
});
export type AiConsentTerms = z.infer<typeof AiConsentTerms>;

/** A consent a member gave and hasn't withdrawn. */
export interface GivenConsent {
  readonly terms: AiConsentTerms;
  readonly givenAt: Date;
}

/** A member's consent as they and the app see it. */
export interface AiConsentState {
  /** What the member must agree to now. */
  readonly terms: AiConsentTerms;
  /** Their latest consent, unless they never gave one or withdrew it. */
  readonly given: GivenConsent | undefined;
  /** Whether `given` is a consent to `terms`. */
  readonly current: boolean;
}

export function sameTerms(a: AiConsentTerms, b: AiConsentTerms): boolean {
  return a.copyVersion === b.copyVersion && a.provider === b.provider;
}

export function stateOf(terms: AiConsentTerms, given: GivenConsent | undefined): AiConsentState {
  return { terms, given, current: given !== undefined && sameTerms(given.terms, terms) };
}
