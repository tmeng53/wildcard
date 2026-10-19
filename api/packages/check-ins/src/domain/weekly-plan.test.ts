import { describe, expect, it } from 'vitest';

import {
  PlanDayStartedError,
  RestDaysFixedError,
  WeekOverError,
  WeekTooFarAheadError,
} from '../errors.js';
import {
  DEFAULT_PLAN_DAYS,
  PlanDay,
  PlanDays,
  WeekStart,
  checkPlanChange,
  localDayAt,
  weekStartOf,
  type PlanDays as Days,
  type WeeklyPlan,
} from './weekly-plan.js';

const train = { kind: 'train' } as const;
const rest = { kind: 'rest' } as const;
const run = { kind: 'train', sport: 'run' } as const;

describe('WeekStart', () => {
  it('is a Monday', () => {
    expect(WeekStart.safeParse('2026-10-19').success).toBe(true);
    expect(WeekStart.safeParse('2026-10-18').success).toBe(false);
    expect(WeekStart.safeParse('2026-10-20').success).toBe(false);
  });
});

describe('weekStartOf', () => {
  it.each([
    ['2026-10-19', '2026-10-19'],
    ['2026-10-21', '2026-10-19'],
    ['2026-10-25', '2026-10-19'],
    ['2026-10-26', '2026-10-26'],
    ['2027-01-01', '2026-12-28'],
  ])('puts %s in the week of %s', (...[day, monday]) => {
    expect(weekStartOf(day)).toBe(monday);
  });
});

describe('localDayAt', () => {
  it.each([
    // 2026-10-19 08:00 UTC is 01:00 in Los Angeles: still Sunday the 18th.
    ['2026-10-19T08:00:00.000Z', 'America/Los_Angeles', '2026-10-18'],
    // 03:00 there: Monday has begun.
    ['2026-10-19T10:00:00.000Z', 'America/Los_Angeles', '2026-10-19'],
    ['2026-10-19T09:59:59.999Z', 'America/Los_Angeles', '2026-10-18'],
    ['2026-10-19T02:59:00.000Z', 'UTC', '2026-10-18'],
    ['2026-10-19T03:00:00.000Z', 'UTC', '2026-10-19'],
    // 2026-10-19 00:30 UTC is 08:30 in Shanghai.
    ['2026-10-19T00:30:00.000Z', 'Asia/Shanghai', '2026-10-19'],
    // The night US clocks fall back (2026-11-01, 02:00 → 01:00): 02:30 PST is 10:30 UTC.
    ['2026-11-01T10:30:00.000Z', 'America/Los_Angeles', '2026-10-31'],
    ['2026-11-01T11:00:00.000Z', 'America/Los_Angeles', '2026-11-01'],
  ])('reads %s in %s as %s', (...[moment, timeZone, day]) => {
    expect(localDayAt(new Date(moment), timeZone)).toBe(day);
  });
});

describe('PlanDay', () => {
  it.each([
    ['a rest day', rest],
    ['a training day with no sport', train],
    ['a listed sport', run],
    ['a custom sport', { kind: 'train', sport: 'custom', customSport: '飞盘' }],
  ])('takes %s', (_case, day) => {
    expect(PlanDay.parse(day)).toStrictEqual(day);
  });

  it.each([
    ['a rest day with a sport', { kind: 'rest', sport: 'run' }],
    ['a custom sport with no name', { kind: 'train', sport: 'custom' }],
    ['a name next to a listed sport', { kind: 'train', sport: 'run', customSport: '飞盘' }],
    ['a name with no sport', { kind: 'train', customSport: '飞盘' }],
    ['a sport not on the list', { kind: 'train', sport: 'quidditch' }],
    ['minutes', { kind: 'train', minutes: 30 }],
    ['another kind', { kind: 'nap' }],
  ])('refuses %s', (_case, day) => {
    expect(PlanDay.safeParse(day).success).toBe(false);
  });

  it('needs exactly seven days', () => {
    expect(PlanDays.safeParse(DEFAULT_PLAN_DAYS.slice(0, 6)).success).toBe(false);
    expect(PlanDays.safeParse([...DEFAULT_PLAN_DAYS, rest]).success).toBe(false);
    expect(PlanDays.parse(DEFAULT_PLAN_DAYS)).toStrictEqual(DEFAULT_PLAN_DAYS);
  });
});

describe('checkPlanChange', () => {
  // Rest on Wednesday and Sunday; Monday is a run.
  const days: Days = [run, train, rest, train, train, train, rest];
  const plan = (source: WeeklyPlan['source'], weekStart = '2026-10-19'): WeeklyPlan => ({
    weekStart,
    days,
    source,
  });
  /** `'allowed'`, or the error the change throws on `today`. */
  const changeOn =
    (today: string, joinedOn = '2026-09-01') =>
    (current: WeeklyPlan, next: Days) => {
      try {
        checkPlanChange({ current, next, today, joinedOn });
        return 'allowed';
      } catch (error) {
        return error;
      }
    };
  // Today is Wednesday.
  const change = changeOn('2026-10-21');

  it('lets a later day swap with a rest day this week', () => {
    // Today is Wednesday: Thursday rests instead of Sunday.
    expect(change(plan('saved'), [run, train, rest, rest, train, train, train])).toBe('allowed');
  });

  it('lets today’s sport change, and keeps the rest days of a carried-over plan', () => {
    const today = '2026-10-19';
    expect(
      changeOn(today)(plan('carriedOver'), [{ kind: 'train', sport: 'swim' }, ...days.slice(1)]),
    ).toBe('allowed');
    expect(
      changeOn(today)(plan('carriedOver'), [run, rest, rest, train, train, train, rest]),
    ).toStrictEqual(new RestDaysFixedError(2));
  });

  it('keeps the number of rest days this week', () => {
    expect(change(plan('saved'), [run, train, rest, rest, train, train, rest])).toStrictEqual(
      new RestDaysFixedError(2),
    );
    expect(change(plan('saved'), [run, train, rest, train, train, train, train])).toStrictEqual(
      new RestDaysFixedError(2),
    );
  });

  it('keeps days before today as they were, sport included', () => {
    expect(change(plan('saved'), [train, train, rest, train, train, train, rest])).toStrictEqual(
      new PlanDayStartedError('2026-10-19'),
    );
    expect(change(plan('saved'), [run, rest, rest, train, train, train, train])).toStrictEqual(
      new PlanDayStartedError('2026-10-20'),
    );
  });

  it('keeps today a rest day once it has begun', () => {
    expect(change(plan('saved'), [run, train, train, rest, train, train, rest])).toStrictEqual(
      new PlanDayStartedError('2026-10-21'),
    );
  });

  it('holds a default plan to the same rules once the member has been here a day', () => {
    expect(change(plan('default'), [rest, rest, rest, train, train, train, train])).toStrictEqual(
      new PlanDayStartedError('2026-10-19'),
    );
  });

  it('lets the whole week change on the day a member joins, while it is on the default', () => {
    const joinedToday = changeOn('2026-10-21', '2026-10-21');
    const allTraining: Days = [train, train, train, train, train, train, train];
    expect(joinedToday(plan('default'), allTraining)).toBe('allowed');
    // Once they have saved, today's kind is fixed like anyone's.
    expect(joinedToday(plan('saved'), allTraining)).toStrictEqual(
      new PlanDayStartedError('2026-10-21'),
    );
  });

  it('lets days before the member joined change, and counts rest days from then', () => {
    // Joined on Tuesday; today is Wednesday.
    const joinedTuesday = changeOn('2026-10-21', '2026-10-20');
    expect(joinedTuesday(plan('default'), [rest, train, rest, train, train, train, rest])).toBe(
      'allowed',
    );
    expect(
      joinedTuesday(plan('default'), [run, rest, rest, train, train, train, train]),
    ).toStrictEqual(new PlanDayStartedError('2026-10-20'));
    expect(
      joinedTuesday(plan('default'), [run, train, rest, train, train, train, train]),
    ).toStrictEqual(new RestDaysFixedError(2));
  });

  it('lets a later week change freely, up to 4 weeks ahead', () => {
    const allRest: Days = [rest, rest, rest, rest, rest, rest, rest];
    expect(change(plan('carriedOver', '2026-10-26'), allRest)).toBe('allowed');
    expect(change(plan('saved', '2026-11-16'), allRest)).toBe('allowed');
    expect(change(plan('saved', '2026-11-23'), allRest)).toStrictEqual(
      new WeekTooFarAheadError('2026-11-23'),
    );
  });

  it('keeps a past week as it was', () => {
    expect(change(plan('saved', '2026-10-12'), days)).toStrictEqual(
      new WeekOverError('2026-10-12'),
    );
    // On its Sunday the week is still the current one.
    expect(changeOn('2026-10-18')(plan('saved', '2026-10-12'), days)).toBe('allowed');
  });
});
