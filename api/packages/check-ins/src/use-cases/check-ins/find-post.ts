import type { CheckInId, MemberId } from '../../domain/check-in.js';
import type { CheckInStore, CommentStore, ReactionStore, SquadMembership } from '../../ports.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';
import type { SquadPost } from './list-squad-check-ins.js';

/**
 * One check-in with its reactions and comments, as the feed shows it, for its author or a
 * teammate who can see it: a post's own page. Its author sees it even from a squad they left. As
 * everywhere, only the responses of members of the squads the viewer sees it through, and the
 * viewer's own. Throws `CheckInNotFoundError` for a check-in they can't see.
 */
export async function findPost(
  deps: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly reactions: ReactionStore;
    readonly comments: CommentStore;
  },
  { id, viewer }: { readonly id: CheckInId; readonly viewer: MemberId },
): Promise<SquadPost> {
  const { checkIn, through } = await findVisibleCheckIn(deps, { id, viewer });
  const [reactions, comments, members, viewerSquads] = await Promise.all([
    deps.reactions.list(id),
    deps.comments.list(id),
    deps.membership.membersOfAny(through),
    deps.membership.squadIdsOf(viewer),
  ]);
  const visible = ({ member }: { readonly member: MemberId }) =>
    member === viewer || members.has(member);
  return {
    checkIn:
      checkIn.member === viewer
        ? checkIn
        : { ...checkIn, audience: checkIn.audience.filter((each) => viewerSquads.has(each)) },
    reactions: reactions.filter(visible),
    comments: comments.filter(visible),
  };
}
