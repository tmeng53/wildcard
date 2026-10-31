import type { CheckInRecord, MemberId } from '../../domain/check-in.js';
import type { DayRange, Unshared } from '../../domain/day-range.js';
import type { CheckInStore } from '../../ports.js';

/**
 * A member's own check-ins for a range of days, newest day first, with their whole audience.
 * Those shared to no squad only when `unshared` asks for them.
 */
export async function listMyCheckIns(
  { store }: { readonly store: CheckInStore },
  {
    member,
    days,
    unshared,
  }: { readonly member: MemberId; readonly days: DayRange; readonly unshared?: Unshared },
): Promise<CheckInRecord[]> {
  const checkIns = await store.listForMember({ ...days, member });
  return unshared === 'include' ? checkIns : checkIns.filter(({ audience }) => audience.length > 0);
}
