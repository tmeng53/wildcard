import { isLeave, type CheckInRecord, type LocalDay } from './check-in.js';
import type { SportKey } from './sports.js';
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

/**
 * A 训练 wins over a 请假条 posted earlier the same day. A 休息 is no 请假条: it made the day a
 * rest day in the plan, which is how the day shows.
 */
export function trainingOn(checkIns: readonly CheckInRecord[], day: LocalDay): TrainingStatus {
  const posts = checkIns.filter((each) => each.day === day);
  if (posts.some(({ kind }) => kind === 'trained')) return 'trained';
  if (posts.some(isLeave)) return 'disclaimer';
  return 'notCheckedIn';
}

/** How a day went for training, as the 出赛表 marks it: the sport of the day's latest 训练. */
export type DayMark =
  | { readonly status: 'trained'; readonly sport: SportKey; readonly customSport?: string }
  | { readonly status: 'disclaimer' }
  | { readonly status: 'none' };

/** A 训练 wins over a 请假条, and the latest 训练 of the day names its sport. */
export function markOn(checkIns: readonly CheckInRecord[], day: LocalDay): DayMark {
  let latest: (CheckInRecord & { readonly kind: 'trained' }) | undefined;
  for (const each of checkIns) {
    if (each.day !== day || each.kind !== 'trained') continue;
    if (latest === undefined || each.createdAt > latest.createdAt) latest = each;
  }
  if (latest !== undefined) {
    const { sport, customSport } = latest.training;
    return { status: 'trained', sport, ...(customSport === undefined ? {} : { customSport }) };
  }
  return trainingOn(checkIns, day) === 'disclaimer' ? { status: 'disclaimer' } : { status: 'none' };
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

/** Days among `days` with a 训练. Several 训练 on one day count once. */
export function trainedDays(checkIns: readonly CheckInRecord[], days: readonly LocalDay[]): number {
  return days.filter((day) => trainingOn(checkIns, day) === 'trained').length;
}

/**
 * The 训练 checked in on `days`, each counting once, several on one day too: what a squad's weekly
 * goal (小队每周目标, 人均 N 次) counts.
 */
export function trainings(checkIns: readonly CheckInRecord[], days: readonly LocalDay[]): number {
  const week = new Set(days);
  return checkIns.filter((each) => each.kind === 'trained' && week.has(each.day)).length;
}

/**
 * When a member reached their `count`-th day trained: the moment the 训练 that made it was
 * checked in (the first 训练 of each day counts, the count-th earliest of them). `undefined`
 * for a count under 1, or while they have trained fewer days.
 */
export function trainedDaysReachedAt(
  checkIns: readonly CheckInRecord[],
  { days, count }: { readonly days: readonly LocalDay[]; readonly count: number },
): Date | undefined {
  if (count < 1) return undefined;
  const firsts = days
    .flatMap((day) => {
      const times = checkIns
        .filter((each) => each.day === day && each.kind === 'trained')
        .map(({ createdAt }) => createdAt.getTime());
      return times.length === 0 ? [] : [Math.min(...times)];
    })
    .toSorted((a, b) => a - b);
  const at = firsts[count - 1];
  return at === undefined ? undefined : new Date(at);
}

/**
 * Orders members by days trained, most first. A tie goes to whoever reached that many days
 * first (`reachedAt`, from `trainedDaysReachedAt`); someone without one comes after anyone
 * with one, and the rest keep the order they came in (the order they joined).
 */
export function byTrainedThenReached<
  Member extends { readonly trainedDays: number; readonly reachedAt?: Date | string | undefined },
>(a: Member, b: Member): number {
  if (a.trainedDays !== b.trainedDays) return b.trainedDays - a.trainedDays;
  const at = (member: Member) =>
    member.reachedAt === undefined
      ? Number.POSITIVE_INFINITY
      : new Date(member.reachedAt).getTime();
  const [x, y] = [at(a), at(b)];
  if (x === y) return 0;
  return x < y ? -1 : 1;
}
