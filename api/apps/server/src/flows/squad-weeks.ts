import { WeekStart } from '@wildcard/check-ins';
import type { Squad, Squads } from '@wildcard/squads';
import { mondayOf, wallClockAt } from '@wildcard/time-zones';

/**
 * The squad's W1: the Monday of the week it was made, on its own clock then. Every 出赛表 counts
 * its weeks from it, so the whole squad shows one week number (Tracy, 2026-11-09), never a count
 * since each member joined.
 */
export async function squadFirstWeek(
  squads: Pick<Squads, 'timeZonesAt'>,
  squad: Pick<Squad, 'id' | 'createdAt'>,
): Promise<WeekStart> {
  const zone = (await squads.timeZonesAt([squad.id], squad.createdAt))(squad.id);
  return WeekStart.parse(mondayOf(wallClockAt(squad.createdAt, zone).day));
}

/** The W1 of `member`'s squad, if they are in one (a member is in one at most). */
export async function memberSquadFirstWeek(
  squads: Pick<Squads, 'timeZonesAt' | 'listMine'>,
  member: Parameters<Squads['listMine']>[0],
): Promise<WeekStart | undefined> {
  const [squad] = await squads.listMine(member);
  return squad === undefined ? undefined : squadFirstWeek(squads, squad);
}
