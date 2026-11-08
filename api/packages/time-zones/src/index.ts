import { z } from 'zod';

// @wildcard/time-zones: how a time zone is named on the wire and in stored rows, and the wall
// clock in one. A member's profile keeps their own zone; a squad keeps one for what its whole
// squad shares (the 战报's Sunday 8pm, the coach's daily wake).

/**
 * An IANA time zone name such as `America/Los_Angeles`, as iOS's `TimeZone.current.identifier`
 * gives it: a name, not an offset, because offsets change with daylight saving. A few names have
 * no area (`UTC`, `GMT`). Whether the zone exists is checked where it is saved (Node's and
 * Postgres's time zone data can differ), so this checks only the shape.
 */
export const TimeZone = z
  .string()
  .regex(/^[A-Za-z][A-Za-z0-9_+-]*(\/[A-Za-z0-9_+-]+)*$/, 'Must be an IANA time zone name')
  .max(64);
export type TimeZone = z.infer<typeof TimeZone>;

/** The zone every squad-wide moment kept before squads had their own, and still keeps without one. */
export const NEW_YORK = 'America/New_York';

/** Whether this runtime knows the zone, so it can tell its wall clock. */
export function isKnownTimeZone(zone: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

/** A moment as a wall clock in a zone shows it. */
export interface WallClock {
  /** `YYYY-MM-DD`. */
  readonly day: string;
  /** 0 to 23. */
  readonly hour: number;
}

const formats = new Map<string, Intl.DateTimeFormat>();

function formatIn(zone: string): Intl.DateTimeFormat {
  let format = formats.get(zone);
  if (format === undefined) {
    format = new Intl.DateTimeFormat('en-US', {
      timeZone: zone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    });
    formats.set(zone, format);
  }
  return format;
}

/** `moment` on the zone's wall clock, written as if that clock were UTC. */
function wallAsUtc(moment: Date, zone: string): number {
  const parts = formatIn(zone).formatToParts(moment);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((candidate) => candidate.type === type)?.value);
  return Date.UTC(
    part('year'),
    part('month') - 1,
    part('day'),
    part('hour'),
    part('minute'),
    part('second'),
  );
}

/** The day and hour `moment` is in the zone. */
export function wallClockAt(moment: Date, zone: string): WallClock {
  const wall = new Date(wallAsUtc(moment, zone));
  return { day: wall.toISOString().slice(0, 10), hour: wall.getUTCHours() };
}

/**
 * The moment the zone's wall clock shows `hour` o'clock on `day` (`YYYY-MM-DD`). A second pass
 * settles a day the offset changes on; an hour daylight saving skips is the hour after it.
 */
export function momentAt({
  day,
  hour,
  zone,
}: {
  readonly day: string;
  readonly hour: number;
  readonly zone: string;
}): Date {
  const wall = Date.parse(day) + hour * 3_600_000;
  const offsetAt = (moment: number) =>
    wallAsUtc(new Date(moment), zone) - Math.floor(moment / 1000) * 1000;
  let moment = wall - offsetAt(wall);
  moment = wall - offsetAt(moment);
  return new Date(moment);
}

/** The Monday of a day's week, `YYYY-MM-DD`: weeks start on Monday. */
export function mondayOf(day: string): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() - ((date.getUTCDay() + 6) % 7));
  return date.toISOString().slice(0, 10);
}
