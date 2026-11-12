import { UNSAVED_MEMBER_ZONE } from '@wildcard/time-zones';
import type { LocalDay, MemberId } from '../../domain/check-in.js';
import { localDayAt } from '../../domain/weekly-plan.js';
import type { MemberCalendar } from '../../ports.js';

/**
 * Each member's time zone, in the order given: their own, else the viewer's, else `UNSAVED_MEMBER_ZONE`; and the
 * day they joined, on that clock, once they have a profile. A squad has at most 8 members, so
 * one calendar read each is fine.
 */
export async function zonesOf(
  calendarOf: MemberCalendar,
  { members, viewer }: { readonly members: readonly MemberId[]; readonly viewer: MemberId },
): Promise<
  { readonly member: MemberId; readonly zone: string; readonly joinedOn: LocalDay | undefined }[]
> {
  const calendars = await Promise.all(members.map((member) => calendarOf(member)));
  const viewerZone = calendars[members.indexOf(viewer)]?.timeZone ?? UNSAVED_MEMBER_ZONE;
  return members.map((member, index) => {
    const calendar = calendars[index];
    const zone = calendar?.timeZone ?? viewerZone;
    return {
      member,
      zone,
      joinedOn: calendar === undefined ? undefined : localDayAt(calendar.joinedAt, zone),
    };
  });
}
