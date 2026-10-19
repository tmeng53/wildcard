import { z } from 'zod';

import type { CheckInRecord, MemberId, SquadId } from './check-in.js';

/**
 * The reactions a teammate can leave on a check-in, from the feed or straight from its push
 * notification. Like Strava's kudos, a member leaves at most one per check-in and can change
 * it. The set is a first draft for Tracy to settle; the app shows each with its own copy.
 */
export const ReactionKind = z.enum(['cheer', 'fire', 'lol']);
export type ReactionKind = z.infer<typeof ReactionKind>;

/** A member's reaction on a check-in. */
export interface Reaction {
  readonly member: MemberId;
  readonly kind: ReactionKind;
  readonly reactedAt: Date;
}

/** What reacting did: a new reaction, a different one in place of the member's last, or nothing. */
export type ReactOutcome = 'created' | 'changed' | 'unchanged';

/**
 * Whether `viewer` may see a check-in: it is their own, or it went to a squad both they and its
 * author are in now (leaving a squad takes your check-ins out of it, as in its feed).
 */
export function canSee(
  checkIn: CheckInRecord,
  {
    viewer,
    viewerSquads,
    authorSquads,
  }: {
    readonly viewer: MemberId;
    readonly viewerSquads: ReadonlySet<SquadId>;
    readonly authorSquads: ReadonlySet<SquadId>;
  },
): boolean {
  if (checkIn.member === viewer) return true;
  return checkIn.audience.some((squad) => viewerSquads.has(squad) && authorSquads.has(squad));
}
