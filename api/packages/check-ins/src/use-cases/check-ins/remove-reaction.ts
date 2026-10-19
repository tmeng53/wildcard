import type { CheckInId, MemberId } from '../../domain/check-in.js';
import type { CheckInStore, ReactionStore, SquadMembership } from '../../ports.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';

/**
 * Takes the member's reaction off a check-in. Safe to repeat. Throws `CheckInNotFoundError` for a
 * check-in they can't see.
 */
export async function removeReaction(
  {
    store,
    membership,
    reactions,
  }: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly reactions: ReactionStore;
  },
  { checkIn, member }: { readonly checkIn: CheckInId; readonly member: MemberId },
): Promise<void> {
  await findVisibleCheckIn({ store, membership }, { id: checkIn, viewer: member });
  await reactions.remove(checkIn, member);
}
