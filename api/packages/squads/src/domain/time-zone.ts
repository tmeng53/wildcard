import {
  NEW_YORK,
  mondayOf,
  wallClockAt,
  weekFreezesAt,
  type TimeZone,
} from '@wildcard/time-zones';

import { SceneWeek } from './scene.js';
import type { MemberId } from './squad.js';
import { weekAfter } from './weekly-goal.js';

// A squad's time zone (小队时区): the clock of what its whole squad shares, the 战报 and awards
// freezing Sunday 8pm and the coach's daily wake. A member's own day keeps their own zone. A
// captain's change counts from the squad's week at once (Tracy, 2026-11-08), unless that week
// would already have frozen on the new clock, when it counts from the next (Tracy, 2026-11-13).

/** One setting of a squad's time zone, and the week (a Monday) it counts from. */
export interface TimeZoneSetting {
  readonly week: SceneWeek;
  readonly timeZone: TimeZone;
  /** Null once the setter deletes their account, and for the squads made before zones. */
  readonly by: MemberId | null;
  readonly at: Date;
}

/**
 * The zone of the week starting `week`: the newest setting counting from that week or before,
 * else New York, as every squad kept before. `settings` are the earliest week first, a week's
 * later settings after its earlier ones.
 */
export function zoneFor(settings: readonly TimeZoneSetting[], week: SceneWeek): TimeZone {
  let zone: TimeZone = NEW_YORK;
  for (const setting of settings) {
    if (setting.week <= week) zone = setting.timeZone;
  }
  return zone;
}

/**
 * The squad's week at `moment` (its Monday): the latest week that has begun on its own zone's
 * clock (a squad's week starts Monday at midnight in that week's zone).
 */
export function weekAt(settings: readonly TimeZoneSetting[], moment: Date): SceneWeek {
  // The squad's week is the Monday on one of its zones' clocks; the earliest always qualifies.
  const candidates = [NEW_YORK, ...settings.map(({ timeZone }) => timeZone)]
    .map((zone) => SceneWeek.parse(mondayOf(wallClockAt(moment, zone).day)))
    .sort()
    .reverse();
  for (const week of candidates) {
    if (mondayOf(wallClockAt(moment, zoneFor(settings, week)).day) >= week) return week;
  }
  throw new Error('No week has begun.');
}

/** The zone the squad keeps at `moment`: its week's (`weekAt`). */
export function zoneAt(settings: readonly TimeZoneSetting[], moment: Date): TimeZone {
  return zoneFor(settings, weekAt(settings, moment));
}

/**
 * The week a captain's change to `zone` at `moment` counts from. At once (Tracy, 2026-11-08): from
 * the squad's week at `moment`, or from the week before when it is still that week on the new
 * clock (a change made on the squad's Monday that is Sunday in the new zone), so the new zone is
 * the squad's zone straight away on every clock. But never from a week whose 战报 would already
 * have frozen on the new clock, Sunday 8pm there (Tracy, 2026-11-13): then from the next week, so
 * a change never freezes a week the squad is still playing.
 */
export function weekOfChange(
  settings: readonly TimeZoneSetting[],
  { zone, moment }: { readonly zone: TimeZone; readonly moment: Date },
): SceneWeek {
  const now = weekAt(settings, moment);
  const there = SceneWeek.parse(mondayOf(wallClockAt(moment, zone).day));
  let week = there < now ? there : now;
  while (weekFreezesAt(week, zone) <= moment) week = weekAfter(week);
  return week;
}
