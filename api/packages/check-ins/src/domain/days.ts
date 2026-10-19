import type { CheckInRecord, LocalDay } from './check-in.js';
import { addDays, weekStartOf } from './weekly-plan.js';

/** A Monday-to-Sunday week (ISO 8601), as weekly plans have it. */
export interface Week {
  readonly from: LocalDay;
  readonly to: LocalDay;
  /** Exactly seven days, `from` first. */
  readonly days: readonly LocalDay[];
}

/** The week `day` is in. */
export function weekOf(day: LocalDay): Week {
  const from = weekStartOf(day);
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
