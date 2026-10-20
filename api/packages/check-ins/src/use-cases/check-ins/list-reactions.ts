import type { CheckInId, MemberId } from '../../domain/check-in.js';
import type { Reaction } from '../../domain/reaction.js';
import type { CheckInStore, ReactionStore, SquadMembership } from '../../ports.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';

/**
 * A check-in's reactions, oldest first, for its author or a teammate who can see it: only those
 * from members of the squads the viewer sees it through, so a reaction never reveals another
 * squad. Throws `CheckInNotFoundError` for a check-in they can't see.
 */
export async function listReactions(
  {
    store,
    membership,
    reactions,
  }: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly reactions: ReactionStore;
  },
  { checkIn: id, viewer }: { readonly checkIn: CheckInId; readonly viewer: MemberId },
): Promise<Reaction[]> {
  const { through } = await findVisibleCheckIn({ store, membership }, { id, viewer });
  const [all, members] = await Promise.all([reactions.list(id), membership.membersOfAny(through)]);
  return all.filter((reaction) => members.has(reaction.member));
}
