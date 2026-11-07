import { NEW_YORK, mondayOf, wallClockAt, type TimeZone } from '@wildcard/time-zones';

import { SceneWeek } from './scene.js';
import type { MemberId } from './squad.js';

// A squad's time zone (小队时区): the clock of what its whole squad shares, the 战报 and awards
// freezing Sunday 8pm and the coach's daily wake. A member's own day keeps their own zone.

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
