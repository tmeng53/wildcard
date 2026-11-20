import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import type { SquadId, Squads } from '@wildcard/squads';
import { wallClockAt } from '@wildcard/time-zones';

/**
 * Today on a member's own clock (their profile's time zone), the day their challenge counts on:
 * it is theirs to take up and mark done until their own midnight, wherever the squad's clock is
 * (Tracy, 2026-11-20). A member with no zone saved yet goes by the squad's.
 */
export async function challengeToday(
  deps: {
    readonly squads: Pick<Squads, 'timeZonesAt'>;
    readonly members: Pick<Members, 'findProfile'>;
  },
  { squad, member, now }: { squad: SquadId; member: string; now: Date },
): Promise<string> {
  const own = await deps.members
    .findProfile(ProfileMember.parse(member))
    .then((profile) => profile?.timeZone)
    .catch(() => undefined);
  const zone = own ?? (await deps.squads.timeZonesAt([squad], now))(squad);
  return wallClockAt(now, zone).day;
}
