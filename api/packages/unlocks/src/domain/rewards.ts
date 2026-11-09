import type { SportId } from '@wildcard/sport-ids';

import type { UnlockKind } from './unlocks.js';

// Everything a member can get is a reward, and each reward says how it is got through its
// triggers, one per way (Tracy, 2026-11-08: "每一个礼品和徽章这些都是有 trigger condition 的"), so
// whether a piece comes from a store, a coach or the team is a row, never a table of its own.

/** The ways a reward is got. */
export const TRIGGER_KINDS = [
  /** The member's 练了 check-ins in its sports. */
  'training',
  /** A squad's AI coach may give it (a piece, at most one a member a week). */
  'coach',
  /** Only the Wildcard team gives it, through admin tools; no coach or rule ever does. */
  'team',
] as const;
export type TriggerKind = (typeof TRIGGER_KINDS)[number];

/** One way a reward is got, with what that way needs. */
export type Trigger =
  | {
      readonly kind: 'training';
      /** False retires the rule: it opens nothing more, and who it opened for keeps it. */
      readonly offered: boolean;
      readonly sports: readonly SportId[];
      readonly after: number;
      readonly countsFrom: Date;
    }
  | { readonly kind: 'coach'; readonly offered: boolean; readonly description?: string }
  | { readonly kind: 'team'; readonly offered: boolean };

/** A store, prop or piece a member can get, and every way they get it. */
export interface Reward {
  readonly kind: UnlockKind;
  readonly id: string;
  readonly triggers: readonly Trigger[];
}
