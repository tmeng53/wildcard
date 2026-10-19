import { describe, expect, it } from 'vitest';

import { CheckInId, Disclaimer, Meal, MemberId, Training, type CheckInRecord } from './check-in.js';
import {
  addDays,
  latestMealOn,
  localDayAt,
  trainedDays,
  trainingOn,
  weekContaining,
  weekdayOf,
} from './days.js';

const at = (iso: string) => new Date(iso);
const member = MemberId.parse('00000000-0000-4000-8000-000000000001');
let next = 0;

/** A check-in of `kind` on `day`, made at 6pm UTC unless `createdAt` says otherwise. */
function checkIn(
  kind: CheckInRecord['kind'],
  {
    day,
    createdAt = `${day}T18:00:00.000Z`,
  }: { readonly day: string; readonly createdAt?: string },
): CheckInRecord {
  next += 1;
  const base = {
    id: CheckInId.parse(`00000000-0000-4000-8000-${String(next).padStart(12, '0')}`),
    member,
    day,
    createdAt: at(createdAt),
    audience: [],
  };
  switch (kind) {
    case 'trained':
      return { ...base, kind, training: Training.parse({ sport: 'run' }) };
    case 'healthyMeal':
    case 'cheatMeal':
      return { ...base, kind, meal: Meal.parse({}) };
    case 'disclaimer':
      return { ...base, kind, disclaimer: Disclaimer.parse({ text: '下雨' }) };
  }
}

describe('localDayAt', () => {
  const toronto = 'America/Toronto';

  it('counts anything before 3am for the day before', () => {
    // 02:59 and 03:00 on the 19th in Toronto (EDT, UTC-4).
    expect(localDayAt(at('2026-10-19T06:59:59.999Z'), toronto)).toBe('2026-10-18');
    expect(localDayAt(at('2026-10-19T07:00:00.000Z'), toronto)).toBe('2026-10-19');
  });

  it('reads the member’s own zone', () => {
    const moment = at('2026-10-19T12:00:00.000Z');
    expect(localDayAt(moment, 'Asia/Tokyo')).toBe('2026-10-19');
    expect(localDayAt(at('2026-10-19T09:00:00.000Z'), 'America/Los_Angeles')).toBe('2026-10-18');
  });

  it('follows daylight saving', () => {
    // 2026-03-08: Toronto jumps from 02:00 to 03:00 EDT. 03:30 EDT is 07:30Z, 01:30 EST is 06:30Z.
    expect(localDayAt(at('2026-03-08T07:30:00.000Z'), toronto)).toBe('2026-03-08');
    expect(localDayAt(at('2026-03-08T06:30:00.000Z'), toronto)).toBe('2026-03-07');
  });
});

describe('weeks', () => {
  it('numbers weekdays from Monday', () => {
    expect(weekdayOf('2026-10-19')).toBe(1);
    expect(weekdayOf('2026-10-25')).toBe(7);
  });

  it('adds days across months and years', () => {
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28');
  });

  it('gives the seven days of the week a day is in', () => {
    expect(weekContaining('2026-10-22', 1).days).toEqual([
      '2026-10-19',
      '2026-10-20',
      '2026-10-21',
      '2026-10-22',
      '2026-10-23',
      '2026-10-24',
      '2026-10-25',
    ]);
    // A week that starts on Sunday: Thursday the 22nd is in the week from Sunday the 18th.
    expect(weekContaining('2026-10-22', 7)).toMatchObject({ from: '2026-10-18', to: '2026-10-24' });
    expect(weekContaining('2026-10-18', 7).from).toBe('2026-10-18');
  });
});

describe('a day’s check-ins', () => {
  it('counts a 练了 after a 免责声明 as trained', () => {
    const day = '2026-10-19';
    expect(trainingOn([checkIn('disclaimer', { day: day })], day)).toBe('disclaimer');
    expect(
      trainingOn([checkIn('disclaimer', { day: day }), checkIn('trained', { day: day })], day),
    ).toBe('trained');
    expect(trainingOn([checkIn('healthyMeal', { day: day })], day)).toBe('notCheckedIn');
    expect(trainingOn([checkIn('trained', { day: '2026-10-18' })], day)).toBe('notCheckedIn');
  });

  it('gives the latest meal', () => {
    const day = '2026-10-19';
    const healthy = checkIn('healthyMeal', { day: day, createdAt: '2026-10-19T18:00:00.000Z' });
    const cheat = checkIn('cheatMeal', { day: day, createdAt: '2026-10-19T20:00:00.000Z' });
    expect(latestMealOn([cheat, healthy], day)).toBe('cheatMeal');
    expect(latestMealOn([healthy], day)).toBe('healthyMeal');
    expect(latestMealOn([checkIn('trained', { day: day })], day)).toBeUndefined();
  });

  it('counts several 练了 on one day once', () => {
    const week = weekContaining('2026-10-19', 1).days;
    const checkIns = [
      checkIn('trained', { day: '2026-10-19' }),
      checkIn('trained', { day: '2026-10-19' }),
      checkIn('disclaimer', { day: '2026-10-20' }),
      checkIn('trained', { day: '2026-10-21' }),
      checkIn('trained', { day: '2026-10-18' }),
    ];
    expect(trainedDays(checkIns, week)).toBe(2);
  });
});
