import { z } from 'zod';

// When a week's awards are given: once for every squad, Sunday at 8pm Eastern (Tracy,
// 2026-10-20), wherever its members live. On the West Coast that is 5pm, so a check-in made
// later on Sunday still counts for the week, only not for its awards.

/** The awards' clock. */
export const AWARDS_TIME_ZONE = 'America/New_York';
/** The hour on Sunday the awards are given, on that clock. */
export const AWARDS_HOUR = 20;

const DAY = 86_400_000;

/** A week's Monday, `YYYY-MM-DD`. */
export const WeekStart = z.iso
  .date()
  .refine((day) => new Date(Date.parse(day)).getUTCDay() === 1, { message: 'Must be a Monday' })
  .brand<'WeekStart'>();
export type WeekStart = z.infer<typeof WeekStart>;

/** The moment the awards of the week from `weekStart` are given: its Sunday at 8pm Eastern. */
export function awardsTimeOf(weekStart: WeekStart): Date {
  // 8pm on Sunday as if the clock were UTC, then moved by the zone's offset at that moment. A
  // second pass settles a day the offset changes on (never a Sunday evening in practice).
  const wall = Date.parse(weekStart) + 6 * DAY + AWARDS_HOUR * 3_600_000;
  let moment = wall - offsetAt(new Date(wall));
  moment = wall - offsetAt(new Date(moment));
  return new Date(moment);
}

/** The latest week whose awards are due at `now`: this week from Sunday 8pm, else last week. */
export function latestAwardedWeek(now: Date): WeekStart {
  const today = Date.parse(wallClockAt(now).toISOString().slice(0, 10));
  const sinceMonday = (new Date(today).getUTCDay() + 6) % 7;
  const monday = WeekStart.parse(new Date(today - sinceMonday * DAY).toISOString().slice(0, 10));
  if (awardsTimeOf(monday) <= now) return monday;
  return WeekStart.parse(new Date(Date.parse(monday) - 7 * DAY).toISOString().slice(0, 10));
}

/** `moment` on the awards' wall clock, written as if that clock were UTC. */
function wallClockAt(moment: Date): Date {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: AWARDS_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(moment);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((candidate) => candidate.type === type)?.value);
  return new Date(
    Date.UTC(
      part('year'),
      part('month') - 1,
      part('day'),
      part('hour'),
      part('minute'),
      part('second'),
    ),
  );
}

/** How far the awards' clock is ahead of UTC at `moment`, in milliseconds (negative: behind). */
function offsetAt(moment: Date): number {
  return wallClockAt(moment).getTime() - Math.floor(moment.getTime() / 1000) * 1000;
}
