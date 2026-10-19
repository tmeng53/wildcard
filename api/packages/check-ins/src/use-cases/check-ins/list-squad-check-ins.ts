import type { CheckInRecord, MemberId, SquadId } from '../../domain/check-in.js';
import type { DayRange } from '../../domain/day-range.js';
import { SquadNotJoinedError } from '../../errors.js';
import type { CheckInStore, SquadMembership } from '../../ports.js';

export interface ListSquadCheckInsInput {
  readonly viewer: MemberId;
  readonly squad: SquadId;
  readonly days: DayRange;
}

/**
 * A squad's check-ins for a range of days, for one of its members. Only check-ins from members
 * still in the squad: leaving a squad takes your check-ins out of it. Someone else's check-in
 * shows only the squads the viewer is in among its audience.
 */
export async function listSquadCheckIns(
  { store, membership }: { readonly store: CheckInStore; readonly membership: SquadMembership },
  { viewer, squad, days }: ListSquadCheckInsInput,
): Promise<CheckInRecord[]> {
  const viewerSquads = await membership.squadIdsOf(viewer);
  if (!viewerSquads.has(squad)) throw new SquadNotJoinedError(squad);
  const members = await membership.membersOf(squad);
  const checkIns = await store.listForSquad({ ...days, squad, members });
  return checkIns.map((checkIn) =>
    checkIn.member === viewer
      ? checkIn
      : { ...checkIn, audience: checkIn.audience.filter((each) => viewerSquads.has(each)) },
  );
}
