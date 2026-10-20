import { z } from 'zod';

import type { CheckInRecord, MemberId, SquadId } from './check-in.js';

/**
 * The reactions a teammate can leave on a check-in in the app: 加油 (`cheer`, also a double tap),
 * 名场面 (`highlight`) and 笑死 (`lol`), with more to come (Tracy, 2026-10-19). Like Strava's kudos,
 * a member leaves at most one per check-in and can change it. The app shows each with its own copy.
 */
export const ReactionKind = z.enum(['cheer', 'highlight', 'lol']);
export type ReactionKind = z.infer<typeof ReactionKind>;

/** A member's reaction on a check-in. */
export interface Reaction {
  readonly member: MemberId;
  readonly kind: ReactionKind;
  readonly reactedAt: Date;
}

/** What saving a reaction or reply did: a new one, a different one in place of the member's last, or nothing. */
export type SaveOutcome = 'created' | 'changed' | 'unchanged';

/**
 * The squads through which `viewer` sees a check-in: those it went to that both they and its
 * author are in now (leaving a squad takes your check-ins out of it, as in its feed). Empty when
 * they can't see it, unless it is their own. Only reactions from members of these squads are
 * shown to them, so a reaction never reveals a squad they aren't in.
 */
export function sharedSquads(
  checkIn: CheckInRecord,
  {
    viewerSquads,
    authorSquads,
  }: {
    readonly viewerSquads: ReadonlySet<SquadId>;
    readonly authorSquads: ReadonlySet<SquadId>;
  },
): SquadId[] {
  return checkIn.audience.filter((squad) => viewerSquads.has(squad) && authorSquads.has(squad));
}
