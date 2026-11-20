import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import type { SquadId, Squads } from '@wildcard/squads';
import { momentAt, wallClockAt } from '@wildcard/time-zones';

/**
 * The squad day whose challenge a member is on now: the one their own day (their profile's time
 * zone) started in, so a challenge is theirs to take up and mark done until their own midnight,
 * wherever the squad's clock is (Tracy, 2026-11-20). Notes are dated on the squad's clock, so a
 * member behind it (Vancouver in a Toronto squad) keeps the squad's today until their midnight,
 * and one ahead of it (Shanghai) gets the squad day whose note reached them on their morning.
 * A member with no zone saved goes by the squad's.
 */
export async function challengeToday(
  deps: {
    readonly squads: Pick<Squads, 'timeZonesAt'>;
    readonly members: Pick<Members, 'findProfile'>;
  },
  { squad, member, now }: { squad: SquadId; member: string; now: Date },
): Promise<string> {
  const own = (await deps.members.findProfile(ProfileMember.parse(member)))?.timeZone;
  const zoneAt = async (moment: Date) => (await deps.squads.timeZonesAt([squad], moment))(squad);
  if (own === undefined) return wallClockAt(now, await zoneAt(now)).day;
  const midnight = momentAt({ day: wallClockAt(now, own).day, hour: 0, zone: own });
  return wallClockAt(midnight, await zoneAt(midnight)).day;
}
