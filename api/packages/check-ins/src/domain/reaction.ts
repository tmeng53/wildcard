import { isOneEmoji } from '@wildcard/typed-text';
import { z } from 'zod';

import type { CheckInRecord, MemberId, SquadId } from './check-in.js';

/**
 * The reaction a teammate leaves on a check-in: any one emoji, like iMessage's (Tracy,
 * 2026-10-20). A member leaves at most one per check-in and can change it.
 */
export const Emoji = z.string().refine(isOneEmoji, 'Not one emoji').brand<'Emoji'>();
export type Emoji = z.infer<typeof Emoji>;

/** A member's reaction on a check-in. */
export interface Reaction {
  readonly member: MemberId;
  readonly emoji: Emoji;
  readonly reactedAt: Date;
}

/** What saving a reaction did: a new one, a different one in place of the member's last, or nothing. */
export type SaveOutcome = 'created' | 'changed' | 'unchanged';

/**
 * The squads through which `viewer` sees a check-in: those it went to that both they and its
 * author are in now (leaving a squad takes your check-ins out of it, as in its feed). Empty when
 * they can't see it, unless it is their own. Only reactions from members of these squads are
 * shown to them, so a reaction never reveals a squad they aren't in.
 */
export function sharedSquads(
  checkIn: Pick<CheckInRecord, 'audience'>,
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
