import type { SportId } from '@wildcard/sport-ids';

import type { MemberId, Trained, Unlock, UnlockRule, UnlockRuleEdit } from './domain/unlocks.js';

/** Where the rules and members' unlocks are kept. */
export interface UnlockStore {
  rules(): Promise<UnlockRule[]>;
  /** Adds a rule counting from now, or changes one, keeping when it counts from. */
  putRule(edit: UnlockRuleEdit): Promise<void>;
  /** What `member` unlocked, the earliest first. */
  unlocksOf(member: MemberId): Promise<Unlock[]>;
  /**
   * Keeps `unlocks` for `member`; one already kept stays as it was. Answers with the ones this
   * call kept, so two at once never both count the same unlock as new.
   */
  grant(member: MemberId, unlocks: readonly Unlock[]): Promise<Unlock[]>;
}

/**
 * Told the unlocks a member just got (by training or as a gift), each once, after they are kept;
 * the server tells the member (通知).
 */
export type Unlocked = (member: MemberId, unlocks: readonly Unlock[]) => Promise<void>;

/** The member's 练了 check-ins made from `since` on, the earliest made first. */
export type TrainedSince = (query: {
  readonly member: MemberId;
  readonly since: Date;
}) => Promise<Trained[]>;

/** Whether `id` is on the sports list. */
export type SportListed = (id: SportId) => Promise<boolean>;
