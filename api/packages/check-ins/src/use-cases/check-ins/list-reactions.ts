import type { CheckInId, MemberId } from '../../domain/check-in.js';
import type { Reaction } from '../../domain/reaction.js';
import type { CheckInStore, ReactionStore } from '../../ports.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';

/**
 * A check-in's reactions, oldest first, for its author or a teammate who can see it. Throws
 * `CheckInNotFoundError` otherwise.
 */
export async function listReactions(
  { store, reactions }: { readonly store: CheckInStore; readonly reactions: ReactionStore },
  { checkIn, viewer }: { readonly checkIn: CheckInId; readonly viewer: MemberId },
): Promise<Reaction[]> {
  await findVisibleCheckIn(store, { id: checkIn, viewer });
  return reactions.list(checkIn);
}
