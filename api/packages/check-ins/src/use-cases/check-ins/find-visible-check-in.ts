import type { CheckInId, CheckInRecord, MemberId, SquadId } from '../../domain/check-in.js';
import { sharedSquads } from '../../domain/reaction.js';
import { CheckInNotFoundError } from '../../errors.js';
import type { CheckInStore, SquadMembership } from '../../ports.js';

/**
 * The check-in, if `viewer` may see it (their own, or posted in the 动态 of a squad they share
 * with its author, after the viewer (last) joined it), with the squads they see it through: none for one only recorded, which
 * reaches nobody else. Throws `CheckInNotFoundError` otherwise, the same
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
  const shared = checkIn.inFeed ? sharedSquads(checkIn, { viewerSquads, authorSquads }) : [];
  // Another's post reaches the viewer through a squad only once they were in it.
  const through =
    checkIn.member === viewer
      ? shared
      : (
          await Promise.all(
            shared.map(async (squad) => {
              const joined = await membership.joinedAt(viewer, squad);
              return joined !== undefined && checkIn.createdAt >= joined ? [squad] : [];
            }),
          )
        ).flat();
  if (checkIn.member !== viewer && (through.length === 0 || !checkIn.inFeed))
    throw new CheckInNotFoundError(id);
  return { checkIn, through };
}
