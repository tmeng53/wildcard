import { MemberId as ProfileMember } from '@wildcard/members';
import type { SquadId, Squads } from '@wildcard/squads';
import { type TimeZone, wallClockAt } from '@wildcard/time-zones';

/**
 * The squad day whose challenge a member is on now: the earlier of today on their own clock (their
 * profile's time zone) and today on the squad's, so a challenge stays theirs to take up and mark
 * done until its day is over on both (Tracy, 2026-11-20). Notes are dated on the squad's clock, so
 * a member behind the squad (Vancouver in a Toronto squad) keeps the day's until their own
 * midnight, and one ahead of it (Shanghai), who gets the squad's note in their evening, keeps it
 * until the squad's. A member with no zone saved goes by the squad's.
 */
export async function challengeToday(
  deps: {
    readonly squads: Pick<Squads, 'timeZonesAt'>;
    /** Only the zone is read, so `Members` fits. */
    readonly members: {
      findProfile(member: ProfileMember): Promise<{ readonly timeZone: TimeZone } | undefined>;
    };
  },
  { squad, member, now }: { squad: SquadId; member: string; now: Date },
): Promise<string> {
  const squadToday = wallClockAt(now, (await deps.squads.timeZonesAt([squad], now))(squad)).day;
  const own = (await deps.members.findProfile(ProfileMember.parse(member)))?.timeZone;
  if (own === undefined) return squadToday;
  const ownToday = wallClockAt(now, own).day;
  return ownToday < squadToday ? ownToday : squadToday;
}
