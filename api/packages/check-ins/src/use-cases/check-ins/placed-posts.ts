import type { CheckInRecord, MemberId, SquadId } from '../../domain/check-in.js';
import { SquadNotJoinedError } from '../../errors.js';
import type { CheckInStore, SquadMembership } from '../../ports.js';

/** The most tagged posts a squad's places are worked out from: its latest ones. */
export const PLACED_POSTS_MAX = 1000;

/**
 * The posts in `squad`'s 动态 tagged with a place, from anyone it went to, newest first, for a
 * member of it: what its places (地点页, 小队地图) are worked out from.
 */
export async function placedPosts(
  { store, membership }: { readonly store: CheckInStore; readonly membership: SquadMembership },
  { squad, viewer }: { readonly squad: SquadId; readonly viewer: MemberId },
): Promise<CheckInRecord[]> {
  if (!(await membership.squadIdsOf(viewer)).has(squad)) throw new SquadNotJoinedError(squad);
  return store.placedForSquad({ squad, limit: PLACED_POSTS_MAX });
}
