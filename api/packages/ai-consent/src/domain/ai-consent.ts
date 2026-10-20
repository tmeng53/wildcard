import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/**
 * The version of the consent copy the app shows, which names the AI providers members' words go
 * to. The copy itself lives in the app's String Catalog; bump this with any change to what it
 * says (another provider included), and every member is asked again.
 */
export const AI_CONSENT_COPY_VERSION = 1;

/** A version of the consent copy. */
export const CopyVersion = z.int().min(1);
export type CopyVersion = z.infer<typeof CopyVersion>;

/** A consent a member gave: to which version of the copy, and when. */
export interface GivenConsent {
  readonly copyVersion: CopyVersion;
  readonly givenAt: Date;
}

/** A member's consent as they and the app see it. */
export interface AiConsentState {
  /** The version of the copy the member must agree to now. */
  readonly copyVersion: CopyVersion;
  /** Their latest consent, unless they never gave one. */
  readonly given: GivenConsent | undefined;
  /** Whether `given` is to `copyVersion`. */
  readonly current: boolean;
}

export function stateOf(copyVersion: CopyVersion, given: GivenConsent | undefined): AiConsentState {
  return { copyVersion, given, current: given?.copyVersion === copyVersion };
}
