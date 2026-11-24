import { SquadId as CoachSquadId, type CoachActivity } from '@wildcard/coach';
import { MemberId as ProfileMember } from '@wildcard/members';
import type { SquadId, Squads } from '@wildcard/squads';
import { momentAt, type TimeZone, wallClockAt } from '@wildcard/time-zones';

/**
 * The squad day whose challenge a member is on now, so a challenge is theirs to take up and mark
 * done until their own midnight, wherever the squad's clock is (Tracy, 2026-11-20). Notes are
 * dated on the squad's clock: it is the squad day their own day (their profile's time zone)
 * started in, which for a member behind the squad (Vancouver in a Toronto squad) is the squad's
 * today until their midnight, or the squad's today once its note has reached them, which for a
 * member ahead of it (Shanghai) comes in their evening. A member with no zone saved goes by the
 * squad's.
 */
export async function challengeToday(
  deps: {
    readonly squads: Pick<Squads, 'timeZonesAt'>;
    /** Only the zone is read, so `Members` fits. */
    readonly members: {
      findProfile(member: ProfileMember): Promise<{ readonly timeZone: TimeZone } | undefined>;
    };
    /** Only whether a challenge reached the member is read, so `CoachActivity` fits. */
    readonly coachActivity: {
      challenge(input: Parameters<CoachActivity['challenge']>[0]): Promise<unknown>;
    };
  },
  { squad, member, now }: { squad: SquadId; member: string; now: Date },
): Promise<string> {
  const zoneAt = async (moment: Date) => (await deps.squads.timeZonesAt([squad], moment))(squad);
  const squadToday = wallClockAt(now, await zoneAt(now)).day;
  const own = (await deps.members.findProfile(ProfileMember.parse(member)))?.timeZone;
  if (own === undefined) return squadToday;
  const midnight = momentAt({ day: wallClockAt(now, own).day, hour: 0, zone: own });
  const started = wallClockAt(midnight, await zoneAt(midnight)).day;
  if (started >= squadToday) return started;
  const reached = await deps.coachActivity.challenge({
    squad: CoachSquadId.parse(squad),
    member,
    today: squadToday,
  });
  return reached === undefined ? started : squadToday;
}
