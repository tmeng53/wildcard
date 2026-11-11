import { describe, expect, it } from 'vitest';

import {
  currentRun,
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

describe('currentRun', () => {
  const days = new Set(['2026-11-02', '2026-11-03', '2026-11-05', '2026-11-06']);

  it('counts back from today, or from yesterday while today has none yet', () => {
    expect(currentRun(days, { today: '2026-11-06' })).toEqual({
      streak: { days: 2, from: '2026-11-05', to: '2026-11-06' },
      brokeOn: '2026-11-04',
    });
    expect(currentRun(days, { today: '2026-11-07' })).toEqual({
      streak: { days: 2, from: '2026-11-05', to: '2026-11-06' },
      brokeOn: '2026-11-04',
    });
  });

  it('is broken once a whole day went by without one', () => {
    expect(currentRun(days, { today: '2026-11-08' })).toEqual({ brokeOn: '2026-11-07' });
  });

  it('lets a planned rest day bridge, even the day before today', () => {
    expect(currentRun(days, { today: '2026-11-06', bridges: new Set(['2026-11-04']) })).toEqual({
      streak: { days: 4, from: '2026-11-02', to: '2026-11-06' },
    });
    expect(currentRun(days, { today: '2026-11-08', bridges: new Set(['2026-11-07']) })).toEqual({
      streak: { days: 2, from: '2026-11-05', to: '2026-11-06' },
      brokeOn: '2026-11-04',
    });
  });

  it('breaks once a whole week went by on rest days alone', () => {
    const week = new Set([
      '2026-11-07',
      '2026-11-08',
      '2026-11-09',
      '2026-11-10',
      '2026-11-11',
      '2026-11-12',
    ]);
    expect(currentRun(days, { today: '2026-11-13', bridges: week })).toEqual({
      streak: { days: 2, from: '2026-11-05', to: '2026-11-06' },
      brokeOn: '2026-11-04',
    });
    expect(
      currentRun(days, { today: '2026-11-14', bridges: new Set([...week, '2026-11-13']) }),
    ).toEqual({
      brokeOn: '2026-11-07',
    });
  });

  it('has nothing without any day', () => {
    expect(currentRun(new Set(), { today: '2026-11-06' })).toEqual({});
  });
});

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

  it('breaks a run on a seventh planned rest day in a row, as the run still going does', () => {
    const rests = (from: number, count: number) =>
      new Set(
        Array.from({ length: count }, (_, i) => `2026-10-${String(from + i).padStart(2, '0')}`),
      );
    const days = new Set(['2026-10-01', '2026-10-02', '2026-10-10']);
    expect(longestRun(days, rests(3, 7))).toEqual({
      days: 2,
      from: '2026-10-01',
      to: '2026-10-02',
    });
    expect(longestRun(new Set(['2026-10-01', '2026-10-08']), rests(2, 6))).toEqual({
      days: 2,
      from: '2026-10-01',
      to: '2026-10-08',
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

  it('puts a training without a start on the hour it was posted, leaving out 补打卡', () => {
    expect(records.hours[19]).toBe(2);
    expect(records.hours[10]).toBe(1);
    expect(records.hours.reduce((sum, count) => sum + count, 0)).toBe(3);
  });

  it('counts days by weekday, Monday first', () => {
    expect(records.weekdays).toEqual([1, 1, 0, 1, 0, 0, 0]);
  });

  it('puts a training on the hour it started: the start picked, else its workout’s', () => {
    const started = memberRecords({
      trainings: [
        // Posted at 11pm in New York, started at 7:30am by hand.
        training({ day: '2026-11-03', hourUtc: 4 }, { startTime: '07:30' }),
        // Posted at 11pm in New York, its Health workout began at 6pm there.
        training(
          { day: '2026-11-03', hourUtc: 4 },
          { workoutStartedAt: new Date('2026-11-03T23:00:00Z') },
        ),
        // Both: the start picked wins over the workout's.
        training(
          { day: '2026-11-04', hourUtc: 4 },
          { startTime: '09:00', workoutStartedAt: new Date('2026-11-04T23:00:00Z') },
        ),
        // A 补打卡 with a start picked keeps it.
        training(
          { day: '2026-11-01', hourUtc: 4 },
          { postedDay: '2026-11-03', startTime: '12:05' },
        ),
      ],
      healthyMealDays: [],
      restDays: new Set(),
      timeZone: NEW_YORK,
    });
    expect(started.hours[7]).toBe(1);
    expect(started.hours[18]).toBe(1);
    expect(started.hours[12]).toBe(1);
    expect(started.hours[9]).toBe(1);
    expect(started.hours[23]).toBe(0);
    expect(started.hours.reduce((sum, count) => sum + count, 0)).toBe(4);
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
