import { mondayOf, momentAt, wallClockAt } from '@wildcard/time-zones';
import { z } from 'zod';

// When a week's awards are given and its 战报 freezes: Sunday at 8pm (Tracy, 2026-10-20) on the
// squad's own clock, its time zone (小队时区, Tracy, 2026-10-23); New York for a squad without
// one. A check-in made later on Sunday still counts for the week, only not for its awards.

/** The hour on Sunday the awards are given, on the squad's clock. */
export const AWARDS_HOUR = 20;

/** The zones furthest ahead of and behind UTC: every squad's Sunday 8pm falls between theirs. */
const EARLIEST_ZONE = 'Etc/GMT-14';
const LATEST_ZONE = 'Etc/GMT+12';

const DAY = 86_400_000;

/** A week's Monday, `YYYY-MM-DD`. */
export const WeekStart = z.iso
  .date()
  .refine((day) => new Date(Date.parse(day)).getUTCDay() === 1, { message: 'Must be a Monday' })
  .brand<'WeekStart'>();
export type WeekStart = z.infer<typeof WeekStart>;

/** The moment the awards of the week from `weekStart` are given: its Sunday at 8pm in `zone`. */
export function awardsTimeOf(weekStart: WeekStart, zone: string): Date {
  const sunday = new Date(Date.parse(weekStart) + 6 * DAY).toISOString().slice(0, 10);
  return momentAt({ day: sunday, hour: AWARDS_HOUR, zone });
}

/** The last moment any squad's awards of the week from `weekStart` are given, in the zone furthest behind. */
export function lastAwardsTimeOf(weekStart: WeekStart): Date {
  return awardsTimeOf(weekStart, LATEST_ZONE);
}

/** The latest week whose awards are due at `now` in `zone`: this week from Sunday 8pm, else last week. */
export function latestAwardedWeek(now: Date, zone: string): WeekStart {
  const monday = WeekStart.parse(mondayOf(wallClockAt(now, zone).day));
  if (awardsTimeOf(monday, zone) <= now) return monday;
  return weekBefore(monday);
}

/**
 * The weeks whose awards may be due somewhere at `now`, the earliest first: the latest awarded
 * week in the zone furthest ahead, the one in the zone furthest behind, and the week before
 * that, for squads still being tried. Which of them is due for one squad is `awardsTimeOf` in its
 * own zone.
 */
export function weeksMaybeAwarded(now: Date): WeekStart[] {
  const latest = latestAwardedWeek(now, EARLIEST_ZONE);
  const behind = latestAwardedWeek(now, LATEST_ZONE);
  return [...new Set([weekBefore(behind), behind, latest])].sort();
}

/** The Monday a week before `week`. */
export function weekBefore(week: WeekStart): WeekStart {
  return WeekStart.parse(new Date(Date.parse(week) - 7 * DAY).toISOString().slice(0, 10));
}
