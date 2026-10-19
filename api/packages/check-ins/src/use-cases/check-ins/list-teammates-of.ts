import type { CheckInRecord, MemberId } from '../../domain/check-in.js';
import type { CheckInStore } from '../../ports.js';

/**
 * Who sees a check-in besides its author: everyone now in a squad it went to that its author is
 * still in. For telling them about it.
 */
export async function listTeammatesOf(
  { store }: { readonly store: CheckInStore },
  checkIn: CheckInRecord,
): Promise<MemberId[]> {
  const authorSquads = await store.squadsOf(checkIn.member);
  const members = await store.membersOf(
    checkIn.audience.filter((squad) => authorSquads.has(squad)),
  );
  return [...members].filter((member) => member !== checkIn.member).sort();
}
