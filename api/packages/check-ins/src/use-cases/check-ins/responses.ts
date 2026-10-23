import type { CheckInId, MemberId } from '../../domain/check-in.js';
import type { CheckInStore, SquadMembership } from '../../ports.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';

// What teammates leave on a check-in, one each (reactions): read and taken off by the store given.

interface Deps {
  readonly store: CheckInStore;
  readonly membership: SquadMembership;
}

/**
 * A check-in's responses, from `list`, oldest first, for its author or a teammate who can see it:
 * only those from members of the squads the viewer sees it through, so a response never reveals
 * another squad. Throws `CheckInNotFoundError` for a check-in they can't see.
 */
export async function listResponses<Response extends { readonly member: MemberId }>(
  {
    store,
    membership,
    list,
  }: Deps & { readonly list: (checkIn: CheckInId) => Promise<Response[]> },
  { checkIn: id, viewer }: { readonly checkIn: CheckInId; readonly viewer: MemberId },
): Promise<Response[]> {
  const { through } = await findVisibleCheckIn({ store, membership }, { id, viewer });
  const [all, members] = await Promise.all([list(id), membership.membersOfAny(through)]);
  return all.filter((response) => members.has(response.member));
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
