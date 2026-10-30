import { describe, expect, it } from 'vitest';

import { CheckInId, Disclaimer, Meal, MemberId, Training, type CheckInRecord } from './check-in.js';
import { latestMealOn, trainedDays, trainingOn, weekOf } from './days.js';

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

describe('weeks', () => {
  it('gives the seven days of the Monday-to-Sunday week a day is in', () => {
    expect(weekOf('2026-10-22')).toStrictEqual({
      from: '2026-10-19',
      to: '2026-10-25',
      days: [
        '2026-10-19',
        '2026-10-20',
        '2026-10-21',
        '2026-10-22',
        '2026-10-23',
        '2026-10-24',
        '2026-10-25',
      ],
    });
    expect(weekOf('2026-10-19').from).toBe('2026-10-19');
    expect(weekOf('2026-10-25').from).toBe('2026-10-19');
    // Across a year end.
    expect(weekOf('2027-01-01')).toMatchObject({ from: '2026-12-28', to: '2027-01-03' });
  });
});

describe('a day’s check-ins', () => {
  it('counts a 练了 after a 请假条 as trained', () => {
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
    const week = weekOf('2026-10-19').days;
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
