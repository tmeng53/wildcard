import { CheckInDayMismatchError, CheckInInTheFutureError, CheckInTooOldError } from '../errors.js';
import type { LocalDay } from './check-in.js';
import { addDays, localDayAt } from './weekly-plan.js';

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/** How long a check-in made offline can wait to sync. */
const OFFLINE_WINDOW = 48 * HOUR;
/** How far ahead of the server a phone's clock may run. */
const CLOCK_SKEW = 5 * MINUTE;

/**
 * Checks a new check-in's moment and day against the server's clock: made at most 48 hours ago
 * and at most 5 minutes ahead, and counted for a day the member had reached when they made it.
 * With their time zone that is their day at that moment (the 3am rule the home summary and plans
 * use) or the day before, never the day after. Without one, any day within one day of the
 * moment's UTC date (every time zone's local date is). Throws the matching error otherwise.
 */
export function checkCheckInTime(
  checkIn: { readonly createdAt: Date; readonly day: LocalDay },
  { now, timeZone }: { readonly now: Date; readonly timeZone: string | undefined },
): void {
  const age = now.getTime() - checkIn.createdAt.getTime();
  if (age > OFFLINE_WINDOW) throw new CheckInTooOldError();
  if (-age > CLOCK_SKEW) throw new CheckInInTheFutureError();
  if (timeZone === undefined) {
    const utcDay = Date.parse(checkIn.createdAt.toISOString().slice(0, 10));
    if (Math.abs(Date.parse(checkIn.day) - utcDay) > DAY) {
      throw new CheckInDayMismatchError(checkIn.day);
    }
    return;
  }
  const theirDay = localDayAt(checkIn.createdAt, timeZone);
  if (checkIn.day !== theirDay && checkIn.day !== addDays(theirDay, -1)) {
    throw new CheckInDayMismatchError(checkIn.day);
  }
}
