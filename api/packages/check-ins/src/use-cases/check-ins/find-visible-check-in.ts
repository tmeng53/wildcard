import type { CheckInId, CheckInRecord, MemberId } from '../../domain/check-in.js';
import { canSee } from '../../domain/reaction.js';
import { CheckInNotFoundError } from '../../errors.js';
import type { CheckInStore } from '../../ports.js';

/**
 * The check-in, if `viewer` may see it. Throws `CheckInNotFoundError` otherwise, the same as
 * for one that doesn't exist.
 */
export async function findVisibleCheckIn(
  store: CheckInStore,
  { id, viewer }: { readonly id: CheckInId; readonly viewer: MemberId },
): Promise<CheckInRecord> {
  const checkIn = await store.find(id);
  if (checkIn === undefined) throw new CheckInNotFoundError(id);
  if (checkIn.member === viewer) return checkIn;
  const [viewerSquads, authorSquads] = await Promise.all([
    store.squadsOf(viewer),
    store.squadsOf(checkIn.member),
  ]);
  if (!canSee(checkIn, { viewer, viewerSquads, authorSquads })) {
    throw new CheckInNotFoundError(id);
  }
  return checkIn;
}
