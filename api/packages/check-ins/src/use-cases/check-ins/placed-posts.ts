import type { CheckInRecord, MemberId, SquadId } from '../../domain/check-in.js';
import { SquadNotJoinedError } from '../../errors.js';
import type { CheckInStore, SquadMembership } from '../../ports.js';

/** The most tagged posts a squad's places are worked out from: its latest ones. */
export const PLACED_POSTS_MAX = 1000;

/**
 * The posts in `squad`'s 动态 tagged with a place, from anyone it went to, newest first, for a
 * member of it: what its places (地点页, 小队地图) are worked out from. Others' posts only from when
 * the viewer (last) joined, as in the feed (Tracy, 2026-11-11).
 */
export async function placedPosts(
  { store, membership }: { readonly store: CheckInStore; readonly membership: SquadMembership },
  { squad, viewer }: { readonly squad: SquadId; readonly viewer: MemberId },
): Promise<CheckInRecord[]> {
  if (!(await membership.squadIdsOf(viewer)).has(squad)) throw new SquadNotJoinedError(squad);
  const [posts, joined] = await Promise.all([
    store.placedForSquad({ squad, limit: PLACED_POSTS_MAX }),
    membership.joinedAt(viewer, squad),
  ]);
  return posts.filter(
    (post) => post.member === viewer || (joined !== undefined && post.createdAt >= joined),
  );
}
