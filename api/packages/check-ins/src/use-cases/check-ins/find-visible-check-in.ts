import type { CheckInId, CheckInRecord, MemberId, SquadId } from '../../domain/check-in.js';
import { sharedSquads } from '../../domain/reaction.js';
import { CheckInNotFoundError } from '../../errors.js';
import type { CheckInStore, SquadMembership } from '../../ports.js';

/**
 * The check-in, if `viewer` may see it (their own, or sent to a squad they share with its
 * author), with the squads they see it through. Throws `CheckInNotFoundError` otherwise, the same
 * as for one that doesn't exist.
 */
export async function findVisibleCheckIn(
  { store, membership }: { readonly store: CheckInStore; readonly membership: SquadMembership },
  { id, viewer }: { readonly id: CheckInId; readonly viewer: MemberId },
): Promise<{ readonly checkIn: CheckInRecord; readonly through: SquadId[] }> {
  const checkIn = await store.find(id);
  if (checkIn === undefined) throw new CheckInNotFoundError(id);
  const [viewerSquads, authorSquads] = await Promise.all([
    membership.squadIdsOf(viewer),
    checkIn.member === viewer
      ? membership.squadIdsOf(viewer)
      : membership.squadIdsOf(checkIn.member),
  ]);
  const through = sharedSquads(checkIn, { viewerSquads, authorSquads });
  if (through.length === 0 && checkIn.member !== viewer) throw new CheckInNotFoundError(id);
  return { checkIn, through };
}
