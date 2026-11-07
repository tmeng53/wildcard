import { NEW_YORK, mondayOf, wallClockAt, type TimeZone } from '@wildcard/time-zones';

import type { SceneWeek } from './scene.js';
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
 * The zone the squad keeps at `moment`: the newest setting whose week has begun on its own clock
 * (a squad's week starts Monday at midnight in its zone), else New York.
 */
export function zoneAt(settings: readonly TimeZoneSetting[], moment: Date): TimeZone {
  for (const setting of [...settings].reverse()) {
    if (mondayOf(wallClockAt(moment, setting.timeZone).day) >= setting.week) {
      return setting.timeZone;
    }
  }
  return NEW_YORK;
}
