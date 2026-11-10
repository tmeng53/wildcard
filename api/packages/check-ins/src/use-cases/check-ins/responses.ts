import type { CheckInId, MemberId } from '../../domain/check-in.js';
import type { CheckInStore, SquadMembership } from '../../ports.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';

// What teammates leave on a check-in, one each (reactions): taken off by the store given.

interface Deps {
  readonly store: CheckInStore;
  readonly membership: SquadMembership;
}

/**
 * Takes the member's response off a check-in, with `remove`. Safe to repeat. Throws
 * `CheckInNotFoundError` for a check-in they can't see.
 */
export async function removeResponse(
  {
    store,
    membership,
    remove,
  }: Deps & { readonly remove: (checkIn: CheckInId, member: MemberId) => Promise<void> },
  { checkIn, member }: { readonly checkIn: CheckInId; readonly member: MemberId },
): Promise<void> {
  await findVisibleCheckIn({ store, membership }, { id: checkIn, viewer: member });
  await remove(checkIn, member);
}
