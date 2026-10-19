import type { CheckInRecord, LocalDay } from './check-in.js';

const DAY = 86_400_000;

/** Hours after midnight that still count for the day before, as on the phone (`DayBoundary`). */
export const GRACE_HOURS = 3;

/** Monday to Sunday, numbered as in ISO 8601. */
export type Weekday = 1 | 2 | 3 | 4 | 5 | 6 | 7;

/** The day `count` days after `day` (before it when negative). */
export function addDays(day: LocalDay, count: number): LocalDay {
  return new Date(Date.parse(day) + count * DAY).toISOString().slice(0, 10);
}

/**
 * A member's day at `moment` on the wall clock of `timeZone`: midnight ends a day, but anything
 * before 3am still counts for the day before, so a late workout lands on the day it was done.
 */
export function localDayAt(moment: Date, timeZone: string): LocalDay {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(moment);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((each) => each.type === type)?.value ?? '';
  const calendarDay = `${part('year')}-${part('month')}-${part('day')}`;
  return Number(part('hour')) < GRACE_HOURS ? addDays(calendarDay, -1) : calendarDay;
}

/** ISO weekdays by `getUTCDay`, which counts Sunday as 0. */
const WEEKDAYS: readonly Weekday[] = [7, 1, 2, 3, 4, 5, 6];

/** The weekday of a day. */
export function weekdayOf(day: LocalDay): Weekday {
  return WEEKDAYS[new Date(Date.parse(day)).getUTCDay()] ?? 1;
}

/** Seven days in a row, from a member's own week-start day. */
export interface Week {
  readonly from: LocalDay;
  readonly to: LocalDay;
  /** Exactly seven days, `from` first. */
  readonly days: readonly LocalDay[];
}

/** The week `day` is in, for a member whose week starts on `weekStart`. */
export function weekContaining(day: LocalDay, weekStart: Weekday): Week {
  const from = addDays(day, -((weekdayOf(day) - weekStart + 7) % 7));
  const days = Array.from({ length: 7 }, (_, offset) => addDays(from, offset));
  return { from, to: addDays(from, 6), days };
}

/**
 * Where a member's day stands for training. There is no "missed": a day without a check-in is
 * simply not checked in yet.
 */
export type TrainingStatus = 'trained' | 'disclaimer' | 'notCheckedIn';

/** A 练了 wins over a 免责声明 posted earlier the same day. */
export function trainingOn(checkIns: readonly CheckInRecord[], day: LocalDay): TrainingStatus {
  const kinds = new Set(checkIns.filter((each) => each.day === day).map(({ kind }) => kind));
  if (kinds.has('trained')) return 'trained';
  if (kinds.has('disclaimer')) return 'disclaimer';
  return 'notCheckedIn';
}

/** The kind of the latest meal checked in on `day`, if any. */
export function latestMealOn(
  checkIns: readonly CheckInRecord[],
  day: LocalDay,
): 'healthyMeal' | 'cheatMeal' | undefined {
  let latest: CheckInRecord | undefined;
  for (const each of checkIns) {
    if (each.day !== day || (each.kind !== 'healthyMeal' && each.kind !== 'cheatMeal')) continue;
    if (latest === undefined || each.createdAt > latest.createdAt) latest = each;
  }
  return latest?.kind === 'healthyMeal' || latest?.kind === 'cheatMeal' ? latest.kind : undefined;
}

/** Days among `days` with a 练了. Several 练了 on one day count once. */
export function trainedDays(checkIns: readonly CheckInRecord[], days: readonly LocalDay[]): number {
  return days.filter((day) => trainingOn(checkIns, day) === 'trained').length;
}
