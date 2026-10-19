import type { MemberId } from '../../domain/check-in.js';
import type { MemberCalendar } from '../../ports.js';

/** The zone for a member who hasn't saved one, when the viewer hasn't either. */
const FALLBACK_ZONE = 'UTC';

/**
 * Each member's time zone, in the order given: their own, else the viewer's, else UTC. A squad
 * has at most 8 members, so one calendar read each is fine.
 */
export async function zonesOf(
  calendarOf: MemberCalendar,
  { members, viewer }: { readonly members: readonly MemberId[]; readonly viewer: MemberId },
): Promise<{ readonly member: MemberId; readonly zone: string }[]> {
  const calendars = await Promise.all(members.map((member) => calendarOf(member)));
  const viewerZone = calendars[members.indexOf(viewer)]?.timeZone ?? FALLBACK_ZONE;
  return members.map((member, index) => ({
    member,
    zone: calendars[index]?.timeZone ?? viewerZone,
  }));
}
