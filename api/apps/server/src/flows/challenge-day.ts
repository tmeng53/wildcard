import { MemberId as ProfileMember } from '@wildcard/members';
import type { SquadId, Squads } from '@wildcard/squads';
import { challengeDay, type TimeZone } from '@wildcard/time-zones';

/**
 * The squad day whose challenge a member is on now (`challengeDay`), from the squad's zone and
 * the member's own. The coach's wakes go by the same rule, so the coach looks up the challenge
 * the member sees.
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
  const squadZone = (await deps.squads.timeZonesAt([squad], now))(squad);
  const own = (await deps.members.findProfile(ProfileMember.parse(member)))?.timeZone;
  return challengeDay(now, { squad: squadZone, own });
}
