import {
  stateOf,
  type AiConsentState,
  type CopyVersion,
  type MemberId,
} from '../../domain/ai-consent.js';
import { AiConsentCopyOutdatedError } from '../../errors.js';
import type { Clock, ConsentStore } from '../../ports.js';

export interface GiveConsentInput {
  readonly member: MemberId;
  /** The version of the copy the app showed the member, which must be the current one. */
  readonly copyVersion: CopyVersion;
}

/**
 * Records the member's consent to the current copy. Safe to repeat: a member who agreed to it
 * already keeps when they did. Throws `AiConsentCopyOutdatedError` for any other version.
 */
export async function giveConsent(
  deps: {
    readonly store: ConsentStore;
    readonly copyVersion: CopyVersion;
    readonly clock: Clock;
  },
  { member, copyVersion }: GiveConsentInput,
): Promise<AiConsentState> {
  if (copyVersion !== deps.copyVersion) throw new AiConsentCopyOutdatedError(copyVersion);
  const kept = await deps.store.give(member, { copyVersion, givenAt: deps.clock() });
  return stateOf(deps.copyVersion, kept);
}
