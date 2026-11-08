import { describe, expect, it } from 'vitest';

import {
  longestRun,
  memberRecords,
  sportDays,
  squadRecords,
  type RecordTraining,
} from './records.js';
import { SportKey } from './sports.js';

const NEW_YORK = 'America/New_York';

/** A 练了 for `day`, posted that day at `hourUtc`, unless `extra` says otherwise. */
function training(
  { day, hourUtc, sport = 'run' }: { day: string; hourUtc: number; sport?: string },
  extra: Partial<RecordTraining> = {},
): RecordTraining {
  return {
    day,
    postedDay: day,
    madeAt: new Date(`${day}T${String(hourUtc).padStart(2, '0')}:00:00Z`),
    sport: SportKey.parse(sport),
    ...extra,
  };
}

describe('longestRun', () => {
  it('counts days in a row, the latest run winning a tie', () => {
    const days = new Set(['2026-10-01', '2026-10-02', '2026-10-05', '2026-10-06']);
    expect(longestRun(days)).toEqual({ days: 2, from: '2026-10-05', to: '2026-10-06' });
  });

  it('lets a planned rest day sit inside a run without breaking or adding to it', () => {
    const days = new Set(['2026-10-01', '2026-10-02', '2026-10-04']);
    expect(longestRun(days, new Set(['2026-10-03']))).toEqual({
      days: 3,
      from: '2026-10-01',
      to: '2026-10-04',
    });
  });

  it('has none without a day', () => {
    expect(longestRun(new Set())).toBeUndefined();
  });
});

describe('memberRecords', () => {
  const records = memberRecords({
    trainings: [
      // 7pm in New York, in November (UTC-5).
      training(
        { day: '2026-11-02', hourUtc: 0, sport: 'run' },
        { minutes: 30, madeAt: new Date('2026-11-03T00:00:00Z') },
      ),
      training(
        { day: '2026-11-03', hourUtc: 0, sport: 'run' },
        { minutes: 95, madeAt: new Date('2026-11-04T00:00:00Z') },
      ),
      training({ day: '2026-11-03', hourUtc: 15, sport: 'tennis' }),
      // A 补打卡 posted two days late: counts as a day, not on the clock.
      training({ day: '2026-11-05', hourUtc: 15, sport: 'strength' }, { postedDay: '2026-11-07' }),
    ],
    healthyMealDays: ['2026-11-01', '2026-11-02', '2026-11-03', '2026-11-05'],
    restDays: new Set(['2026-11-04']),
    timeZone: NEW_YORK,
  });

  it('counts days, minutes and the longest single training', () => {
    expect(records.trainedDays).toBe(3);
    expect(records.minutes).toBe(125);
    expect(records.longestMinutes).toBe(95);
  });

  it('bridges the planned rest day in the training streak but not the meal streak', () => {
    expect(records.longestStreak).toEqual({ days: 3, from: '2026-11-02', to: '2026-11-05' });
    expect(records.mealStreak).toEqual({ days: 3, from: '2026-11-01', to: '2026-11-03' });
  });

  it('puts each training on the clock of the hour it was posted, leaving out 补打卡', () => {
    expect(records.hours[19]).toBe(2);
    expect(records.hours[10]).toBe(1);
    expect(records.hours.reduce((sum, count) => sum + count, 0)).toBe(3);
  });

  it('counts days by weekday, Monday first', () => {
    expect(records.weekdays).toEqual([1, 1, 0, 1, 0, 0, 0]);
  });

  it('ranks sports by days', () => {
    expect(records.sports[0]).toEqual({ sport: 'run', days: 2 });
    expect(records.sportCount).toBe(3);
  });
});

describe('squadRecords', () => {
  const me = memberRecords({
    trainings: [
      training({ day: '2026-11-02', hourUtc: 0 }),
      training({ day: '2026-11-03', hourUtc: 0 }),
      training({ day: '2026-11-04', hourUtc: 0 }),
    ],
    healthyMealDays: [],
    restDays: new Set(),
    timeZone: NEW_YORK,
  });
  const cocoTrainings = [
    training({ day: '2026-11-02', hourUtc: 13, sport: 'yoga' }),
    training({ day: '2026-11-03', hourUtc: 13, sport: 'yoga' }),
  ];
  const coco = memberRecords({
    trainings: cocoTrainings,
    healthyMealDays: [],
    restDays: new Set(),
    timeZone: NEW_YORK,
  });

  it('names the partner, the cheers and what the member is first at', () => {
    const squad = squadRecords({
      me: { records: me, days: new Set(['2026-11-02', '2026-11-03', '2026-11-04']) },
      mates: new Map([
        [
          'coco',
          {
            records: coco,
            days: new Set(['2026-11-02', '2026-11-03']),
            sportDays: sportDays(cocoTrainings),
          },
        ],
      ]),
      received: new Map([['coco', 23]]),
      given: new Map([['coco', 41]]),
    });
    expect(squad.partner).toEqual({ member: 'coco', count: 2 });
    expect(squad.cheersReceived).toEqual({ count: 23, top: { member: 'coco', count: 23 } });
    expect(squad.cheersGiven).toEqual({ count: 41, top: { member: 'coco', count: 41 } });
    expect(squad.firsts).toEqual(['latestTrainer', 'topSport', 'mostDays']);
  });

  it('counts a squadmate’s every sport, not only their top ones, for the top sport', () => {
    const days = ['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04', '2026-10-05'];
    const trainings = [
      ...['yoga', 'swim', 'cycling'].flatMap((sport) =>
        days.map((day) => training({ day, hourUtc: 13, sport })),
      ),
      ...days.slice(0, 4).map((day) => training({ day, hourUtc: 13 })),
    ];
    const busy = memberRecords({
      trainings,
      healthyMealDays: [],
      restDays: new Set(),
      timeZone: NEW_YORK,
    });
    expect(busy.sports.map((sport) => sport.sport)).not.toContain('run');
    const squad = squadRecords({
      me: { records: me, days: new Set(['2026-11-02', '2026-11-03', '2026-11-04']) },
      mates: new Map([
        ['busy', { records: busy, days: new Set(days), sportDays: sportDays(trainings) }],
      ]),
      received: new Map(),
      given: new Map(),
    });
    expect(squad.firsts).not.toContain('topSport');
  });

  it('is first at nothing alone', () => {
    const squad = squadRecords({
      me: { records: me, days: new Set() },
      mates: new Map(),
      received: new Map(),
      given: new Map(),
    });
    expect(squad.firsts).toEqual([]);
    expect(squad.partner).toBeUndefined();
    expect(squad.cheersReceived).toEqual({ count: 0 });
  });
});
