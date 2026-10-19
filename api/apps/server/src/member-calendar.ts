import type { MemberCalendar } from '@wildcard/check-ins';
import type { Members } from '@wildcard/members';

/** The weekly plans' view of a member: their time zone and when they joined, from members. */
export function memberCalendar(members: Members): MemberCalendar {
  return async (member) => {
    const [profile, joinedAt] = await Promise.all([
      members.findProfile(member),
      members.joinedAt(member),
    ]);
    if (profile === undefined || joinedAt === undefined) return undefined;
    return { timeZone: profile.timeZone, joinedAt };
  };
}
