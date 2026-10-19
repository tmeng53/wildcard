import { isDeepStrictEqual } from 'node:util';

import { z } from 'zod';

import {
  PlanDayStartedError,
  RestDaysFixedError,
  WeekOverError,
  WeekTooFarAheadError,
} from '../errors.js';
import { LocalDay } from './check-in.js';
import { SportKey } from './sports.js';
import { CustomSportName } from './text.js';

// A member's weekly plan, as the app's contract has it (`WeeklyPlan` in ios/Packages/Contracts):
// seven days, Monday first, each a training day (optionally naming the sport) or a rest day.
// 本周 x/y counts 练了 days against the plan's training days.

const DAY = 86_400_000;

/** Hours after midnight that still count for the day before, as in the app's `DayBoundary`. */
const GRACE_HOURS = 3;

/** How many weeks ahead of the current one a member may plan. */
export const WEEKS_AHEAD = 4;

/** A week, named by its Monday (ISO 8601 weeks, as the plan's W42). */
export const WeekStart = LocalDay.refine((day) => weekdayOf(day) === 1, {
  message: 'A week starts on a Monday',
});
export type WeekStart = z.infer<typeof WeekStart>;

/** One planned day: train, optionally naming the sport, or rest. */
export const PlanDay = z
  .discriminatedUnion('kind', [
    z.strictObject({
      kind: z.literal('train'),
      sport: SportKey.optional(),
      customSport: CustomSportName.optional(),
    }),
    z.strictObject({ kind: z.literal('rest') }),
  ])
  .superRefine((day, context) => {
    if (day.kind === 'rest') return;
    if (day.sport === 'custom' && day.customSport === undefined) {
      context.addIssue({ code: 'custom', path: ['customSport'], message: 'Name the custom sport' });
    }
    if (day.sport !== 'custom' && day.customSport !== undefined) {
      context.addIssue({
        code: 'custom',
        path: ['customSport'],
        message: 'Only a custom sport has a name',
      });
    }
  });
export type PlanDay = z.infer<typeof PlanDay>;

/**
 * Exactly seven days, Monday first. Written as `min` and `max`, which the OpenAPI document
 * states as `minItems` and `maxItems`; it drops `length`.
 */
export const PlanDays = z.array(PlanDay).min(7).max(7);
export type PlanDays = z.infer<typeof PlanDays>;

/** How many of a plan's days are training days. */
export const plannedTrainingDays = (days: readonly PlanDay[]) =>
  days.filter(({ kind }) => kind === 'train').length;

/** The stored plan JSON (`weekly_plans.payload`), versioned like every stored shape. */
export const StoredPlan = z.discriminatedUnion('version', [
  z.strictObject({ version: z.literal(1), days: PlanDays }),
]);

/** The plan a member has before they first save one: rest on Wednesday and Sunday. */
export const DEFAULT_PLAN_DAYS: PlanDays = [
  { kind: 'train' },
  { kind: 'train' },
  { kind: 'rest' },
  { kind: 'train' },
  { kind: 'train' },
  { kind: 'train' },
  { kind: 'rest' },
];

/**
 * Where a week's plan comes from: saved for this week, carried over from the member's latest
 * earlier plan (they haven't changed it since), or the default before their first save.
 */
export type PlanSource = 'saved' | 'carriedOver' | 'default';

export interface WeeklyPlan {
  readonly weekStart: WeekStart;
  readonly days: PlanDays;
  readonly source: PlanSource;
}

/** 1 for Monday to 7 for Sunday, as in ISO 8601. */
function weekdayOf(day: LocalDay): number {
  const weekday = new Date(Date.parse(day)).getUTCDay();
  return weekday === 0 ? 7 : weekday;
}

/** The day `count` days after `day` (before it when negative). */
export function addDays(day: LocalDay, count: number): LocalDay {
  return new Date(Date.parse(day) + count * DAY).toISOString().slice(0, 10);
}

/** The Monday of the week `day` is in. */
export function weekStartOf(day: LocalDay): WeekStart {
  return WeekStart.parse(addDays(day, 1 - weekdayOf(day)));
}

/**
 * The member's day at `moment` on the wall clock of `timeZone` (an IANA name). Before 3am it
 * is still the day before, so a late workout logged after midnight counts for the day it was done.
 */
export function localDayAt(moment: Date, timeZone: string): LocalDay {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(moment);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((candidate) => candidate.type === type)?.value ?? '';
  const calendarDay = LocalDay.parse(`${part('year')}-${part('month')}-${part('day')}`);
  return Number(part('hour')) < GRACE_HOURS ? addDays(calendarDay, -1) : calendarDay;
}

const restDays = (days: readonly PlanDay[]) => days.filter((day) => day.kind === 'rest').length;

/**
 * Checks that a member may replace `current` (the week's plan as it stands) with `next` on
 * `today`, and throws the matching error otherwise. Past weeks are read-only and a member plans
 * at most `WEEKS_AHEAD` weeks ahead; later weeks change freely. In the current week, from the
 * day the member joined (`joinedOn`, the week's Monday for anyone who joined before it):
 * days before today stay as they were, today stays a training or a rest day (its sport may
 * change), and the number of rest days stays the same. Days before the member joined weren't
 * theirs, so they change freely, and so does the whole week on the day a member joins, while it
 * is still on the default plan: that is where they first make their plan.
 */
export function checkPlanChange({
  current,
  next,
  today,
  joinedOn,
}: {
  readonly current: WeeklyPlan;
  readonly next: PlanDays;
  readonly today: LocalDay;
  readonly joinedOn: LocalDay;
}): void {
  const thisWeek = weekStartOf(today);
  if (current.weekStart < thisWeek) throw new WeekOverError(current.weekStart);
  if (current.weekStart > addDays(thisWeek, 7 * WEEKS_AHEAD)) {
    throw new WeekTooFarAheadError(current.weekStart);
  }
  if (current.weekStart > thisWeek) return;
  if (current.source === 'default' && joinedOn >= today) return;

  const from = joinedOn > thisWeek ? joinedOn : thisWeek;
  const first = Math.round((Date.parse(from) - Date.parse(thisWeek)) / DAY);
  for (let index = first; index < 7; index += 1) {
    const date = addDays(thisWeek, index);
    if (date > today) break;
    const before = current.days[index];
    const after = next[index];
    const unchanged =
      date < today ? isDeepStrictEqual(before, after) : before?.kind === after?.kind;
    if (!unchanged) throw new PlanDayStartedError(date);
  }
  const kept = restDays(current.days.slice(first));
  if (restDays(next.slice(first)) !== kept) throw new RestDaysFixedError(kept);
}
