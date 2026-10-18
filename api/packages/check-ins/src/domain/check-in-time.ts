import { CheckInDayMismatchError, CheckInInTheFutureError, CheckInTooOldError } from '../errors.js';
import type { LocalDay } from './check-in.js';

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/** How long a check-in made offline can wait to sync. */
const OFFLINE_WINDOW = 48 * HOUR;
/** How far ahead of the server a phone's clock may run. */
const CLOCK_SKEW = 5 * MINUTE;

/**
 * Checks a new check-in's moment and day against the server's clock: made at most 48 hours ago
 * and at most 5 minutes ahead, and counted for a day within one day of that moment's UTC date
 * (every time zone's local date is). Throws the matching error otherwise.
 */
export function checkCheckInTime(
  checkIn: { readonly createdAt: Date; readonly day: LocalDay },
  now: Date,
): void {
  const age = now.getTime() - checkIn.createdAt.getTime();
  if (age > OFFLINE_WINDOW) throw new CheckInTooOldError();
  if (-age > CLOCK_SKEW) throw new CheckInInTheFutureError();
  const utcDay = Date.parse(checkIn.createdAt.toISOString().slice(0, 10));
  if (Math.abs(Date.parse(checkIn.day) - utcDay) > DAY) {
    throw new CheckInDayMismatchError(checkIn.day);
  }
}
