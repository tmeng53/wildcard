import type { CopyVersion, GivenConsent, MemberId } from './domain/ai-consent.js';

/** Where members' consents are kept, one for each version of the copy they agreed to. */
export interface ConsentStore {
  /** The member's consent to the latest version they agreed to. */
  latest(member: MemberId): Promise<GivenConsent | undefined>;
  /**
   * Records a consent the member gave. Returns the one kept: an earlier consent to the same
   * version stays as it was.
   */
  give(member: MemberId, consent: GivenConsent): Promise<GivenConsent>;
  /** Those of `members` who have agreed to `copyVersion`. */
  agreedTo(copyVersion: CopyVersion, members: readonly MemberId[]): Promise<ReadonlySet<MemberId>>;
}

/** The current time. */
export type Clock = () => Date;
