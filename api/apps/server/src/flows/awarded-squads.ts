import { WeekStart as CheckInWeek, type CheckIns } from '@wildcard/check-ins';
import { SquadId, type Squads } from '@wildcard/squads';
import { awardsTimeOf, lastAwardsTimeOf, type WeekStart } from '@wildcard/weekly-awards';

// Which squads' week has ended, Sunday 8pm on each one's own clock (小队时区), across check-ins
// (who checked in for the week) and squads (each one's zone that week).

/** When a squad's week ended, on which clock. */
export interface Awarded {
  readonly zone: string;
  readonly at: Date;
}

/**
 * The squads whose awards of `week` are due now, by id: those with a check-in for the week made
 * before their own Sunday 8pm, and those `waiting` names (a frozen 战报 still waiting for its
 * titles, though the check-ins that started it were deleted since). A squad that ended
 * (everyone left) gets none: nobody is there to read them, and no AI is spent on it.
 */
export async function squadsAwardedIn(
  deps: {
    readonly checkIns: Pick<CheckIns, 'squadsCheckedInto'>;
    readonly squads: Pick<Squads, 'timeZonesFor' | 'endedAmong'>;
    readonly clock: () => Date;
    readonly waiting?: (week: WeekStart) => Promise<readonly string[]>;
  },
  week: WeekStart,
): Promise<ReadonlyMap<string, Awarded>> {
  const now = deps.clock();
  const last = lastAwardsTimeOf(week);
  const checkedInBefore = async (before: Date) =>
    new Set<string>(
      await deps.checkIns.squadsCheckedInto({ weekStart: CheckInWeek.parse(week), before }),
    );
  const [checkedIn, waiting] = await Promise.all([
    checkedInBefore(last < now ? last : now),
    deps.waiting?.(week) ?? Promise.resolve([]),
  ]);
  const stillWaiting = new Set<string>(waiting);
  const named = [...new Set([...checkedIn, ...stillWaiting])].map((squad) => SquadId.parse(squad));
  const ended = await deps.squads.endedAmong(named);
  const candidates = named.filter((squad) => !ended.has(squad));
  const zones = await deps.squads.timeZonesFor(candidates, week);
  const due = new Map<string, Awarded>();
  for (const squad of candidates) {
    const zone = zones(squad);
    const at = awardsTimeOf(week, zone);
    if (at <= now) due.set(squad, { zone, at });
  }
  // A squad counts only with a check-in before its own moment: asked once for each moment.
  for (const moment of new Set([...due.values()].map(({ at }) => at.getTime()))) {
    const before = await checkedInBefore(new Date(moment));
    for (const [squad, { at }] of due) {
      if (at.getTime() === moment && !before.has(squad) && !stillWaiting.has(squad)) {
        due.delete(squad);
      }
    }
  }
  return due;
}
