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

/** A 练了 wins over a 请假条 posted earlier the same day. */
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

/**
 * When a member finished their week's plan: the moment the 练了 that made their trained days
 * reach the days they planned was checked in (the first 练了 of each day counts, the planned
 * count-th earliest of them). `undefined` without a plan, or while they are still short of it.
 */
export function planFinishedAt(
  checkIns: readonly CheckInRecord[],
  days: readonly LocalDay[],
  plannedDays: number,
): Date | undefined {
  if (plannedDays < 1) return undefined;
  const firsts = days
    .flatMap((day) => {
      const times = checkIns
        .filter((each) => each.day === day && each.kind === 'trained')
        .map(({ createdAt }) => createdAt.getTime());
      return times.length === 0 ? [] : [Math.min(...times)];
    })
    .toSorted((a, b) => a - b);
  const at = firsts[plannedDays - 1];
  return at === undefined ? undefined : new Date(at);
}

/**
 * Orders members by days trained, most first. A tie goes to whoever finished their own plan
 * first (`planFinishedAt`); someone who hasn't finished it comes after anyone who has, and the
 * rest keep the order they came in (the order they joined).
 */
export function byTrainedThenFinished<
  Member extends { readonly trainedDays: number; readonly planFinishedAt?: Date | string },
>(a: Member, b: Member): number {
  if (a.trainedDays !== b.trainedDays) return b.trainedDays - a.trainedDays;
  const at = (member: Member) =>
    member.planFinishedAt === undefined
      ? Number.POSITIVE_INFINITY
      : new Date(member.planFinishedAt).getTime();
  const [x, y] = [at(a), at(b)];
  if (x === y) return 0;
  return x < y ? -1 : 1;
}
