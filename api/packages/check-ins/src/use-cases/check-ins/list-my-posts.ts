import type { MemberId, SquadId } from '../../domain/check-in.js';
import { cursorAfter, type CheckInKind, type PostCursor } from '../../domain/post-cursor.js';
import { sharedSquads } from '../../domain/reaction.js';
import type { CheckInStore, ReactionStore, SquadMembership } from '../../ports.js';
import type { SquadPost } from './list-squad-check-ins.js';

export interface ListMyPostsInput {
  readonly member: MemberId;
  readonly kind?: CheckInKind | undefined;
  /** Where the page starts: after the last check-in of the page before; none for the newest. */
  readonly after?: PostCursor | undefined;
  readonly limit: number;
}

/** One page of a member's history (历史动态). */
export interface MyPostsPage {
  readonly posts: readonly SquadPost[];
  /** Where the next page starts; none when this page reaches the member's first check-in. */
  readonly next?: PostCursor;
  /**
   * Everything they ever posted and the reactions on it they can see, on the first page only
   * (no `after`): the page's header. Neither narrows to `kind`.
   */
  readonly counts?: { readonly posts: number; readonly reactions: number };
}

/**
 * A member's own check-ins, wherever they went, newest first, a page at a time, each with the
 * reactions they see on it: as everywhere, only those from members of the squads they share now
 * among the ones it went to, so a squad they left takes its teammates' reactions with it.
 */
export async function listMyPosts(
  {
    store,
    membership,
    reactions,
  }: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly reactions: ReactionStore;
  },
  { member, kind, after, limit }: ListMyPostsInput,
): Promise<MyPostsPage> {
  const [checkIns, squads] = await Promise.all([
    // One more than asked says whether another page follows.
    store.pageForMember({ member, kind, after, limit: limit + 1 }),
    membership.squadIdsOf(member),
  ]);
  const page = checkIns.slice(0, limit);
  const membersOf = new Map<SquadId, ReadonlySet<MemberId>>(
    await Promise.all(
      [...squads].map(
        async (squad) => [squad, new Set(await membership.membersOf(squad))] as const,
      ),
    ),
  );
  // The member is the author, so they see each check-in through the squads it went to that they're in.
  const visible = (audience: readonly SquadId[]) => (from: MemberId) =>
    sharedSquads({ audience }, { viewerSquads: squads, authorSquads: squads }).some(
      (squad) => membersOf.get(squad)?.has(from) === true,
    );
  const reactionsOf = await reactions.listForAll(page.map(({ id }) => id));
  const posts = page.map((checkIn) => ({
    checkIn,
    reactions: (reactionsOf.get(checkIn.id) ?? []).filter(({ member: from }) =>
      visible(checkIn.audience)(from),
    ),
  }));
  const last = page.at(-1);
  const next = checkIns.length > limit && last !== undefined ? cursorAfter(last) : undefined;
  if (after !== undefined) return next === undefined ? { posts } : { posts, next };

  const [count, received] = await Promise.all([
    store.countForMember(member),
    // Every reaction ever: `until` is the latest moment a Date holds.
    reactions.receivedBy({ member, since: new Date(0), until: new Date(8.64e15) }),
  ]);
  const counts = {
    posts: count,
    reactions: received.filter(({ member: from, audience }) => visible(audience)(from)).length,
  };
  return next === undefined ? { posts, counts } : { posts, next, counts };
}
