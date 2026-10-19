import type { CheckInRecord, MemberId } from '../../domain/check-in.js';
import type { DayRange } from '../../domain/day-range.js';
import type { CheckInStore } from '../../ports.js';

/** A member's own check-ins for a range of days, newest day first, with their whole audience. */
export function listMyCheckIns(
  { store }: { readonly store: CheckInStore },
  { member, days }: { readonly member: MemberId; readonly days: DayRange },
): Promise<CheckInRecord[]> {
  return store.listForMember({ ...days, member });
}
