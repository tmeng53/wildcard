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
/** How many days before the one it's posted on a check-in may count for (补打卡, Tracy, 2026-11-03). */
export const BACKFILL_DAYS = 7;

/**
 * Checks a new check-in's moment and day against the server's clock, and gives the day it was
 * posted on. Made at most 48 hours ago and at most 5 minutes ahead; posted on the member's day at
 * that moment, with their time zone (the 3am rule the home summary and plans use); and counted for
 * that day or one of the 7 before it (补打卡), never a later one. Without a time zone, the day
 * posted on is the one it counts for when that is within one day of the moment's UTC date (every
 * time zone's local date is), else the UTC date, which it may count up to 7 days before. Throws
 * the matching error otherwise.
 */
export function checkCheckInTime(
  checkIn: { readonly createdAt: Date; readonly day: LocalDay },
  { now, timeZone }: { readonly now: Date; readonly timeZone: string | undefined },
): LocalDay {
  const age = now.getTime() - checkIn.createdAt.getTime();
  if (age > OFFLINE_WINDOW) throw new CheckInTooOldError();
  if (-age > CLOCK_SKEW) throw new CheckInInTheFutureError();
  const postedDay = postedDayOf(checkIn, timeZone);
  if (checkIn.day > postedDay || checkIn.day < addDays(postedDay, -BACKFILL_DAYS)) {
    throw new CheckInDayMismatchError(checkIn.day);
  }
  return postedDay;
}

function postedDayOf(
  { createdAt, day }: { readonly createdAt: Date; readonly day: LocalDay },
  timeZone: string | undefined,
): LocalDay {
  if (timeZone !== undefined) return localDayAt(createdAt, timeZone);
  const utcDay = createdAt.toISOString().slice(0, 10);
  return Math.abs(Date.parse(day) - Date.parse(utcDay)) <= DAY ? day : utcDay;
}
