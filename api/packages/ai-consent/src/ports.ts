import type { AiConsentTerms, GivenConsent, MemberId } from './domain/ai-consent.js';

/** Where members' consents are kept, each one given as a record of its own. */
export interface ConsentStore {
  /** The member's latest consent that isn't withdrawn. */
  latest(member: MemberId): Promise<GivenConsent | undefined>;
  /** Records a consent the member gave. */
  give(member: MemberId, consent: GivenConsent): Promise<void>;
  /** Withdraws every consent the member has given. Nothing happens if there are none. */
  withdraw(member: MemberId, at: Date): Promise<void>;
  /** Those of `members` whose latest consent that isn't withdrawn is to `terms`. */
  consentingTo(terms: AiConsentTerms, members: readonly MemberId[]): Promise<ReadonlySet<MemberId>>;
}

/** The current time. */
export type Clock = () => Date;
