import { describe, expect, it } from 'vitest';

import { WeekStart, awardsTimeOf, latestAwardedWeek, weeksMaybeAwarded } from './schedule.js';

const week = (day: string) => WeekStart.parse(day);
const NEW_YORK = 'America/New_York';

describe('awardsTimeOf', () => {
  it('is the week’s Sunday at 8pm on the squad’s clock, in daylight time and in standard time', () => {
    expect(awardsTimeOf(week('2026-10-19'), NEW_YORK).toISOString()).toBe(
      '2026-10-26T00:00:00.000Z',
    );
    // Daylight saving ends on Sunday 2026-11-01 at 2am; 8pm that evening is standard time.
    expect(awardsTimeOf(week('2026-10-26'), NEW_YORK).toISOString()).toBe(
      '2026-11-02T01:00:00.000Z',
    );
    expect(awardsTimeOf(week('2027-01-04'), NEW_YORK).toISOString()).toBe(
      '2027-01-11T01:00:00.000Z',
    );
    // Daylight saving starts on Sunday 2027-03-14.
    expect(awardsTimeOf(week('2027-03-08'), NEW_YORK).toISOString()).toBe(
      '2027-03-15T00:00:00.000Z',
    );
  });

  it('follows the squad’s own zone', () => {
    expect(awardsTimeOf(week('2026-11-02'), 'Asia/Taipei').toISOString()).toBe(
      '2026-11-08T12:00:00.000Z',
    );
    expect(awardsTimeOf(week('2026-11-02'), 'America/Los_Angeles').toISOString()).toBe(
      '2026-11-09T04:00:00.000Z',
    );
  });
});

describe('latestAwardedWeek', () => {
  it('is last week until Sunday 8pm on the squad’s clock, then this week', () => {
    // Sunday 7:59pm in New York (4:59pm in Los Angeles).
    expect(latestAwardedWeek(new Date('2026-10-25T23:59:59.000Z'), NEW_YORK)).toBe('2026-10-12');
    expect(latestAwardedWeek(new Date('2026-10-26T00:00:00.000Z'), NEW_YORK)).toBe('2026-10-19');
    // Monday morning in New York: still the week that just ended.
    expect(latestAwardedWeek(new Date('2026-10-26T13:00:00.000Z'), NEW_YORK)).toBe('2026-10-19');
    expect(latestAwardedWeek(new Date('2026-10-31T12:00:00.000Z'), NEW_YORK)).toBe('2026-10-19');
    // Sunday 8pm in Taipei is Sunday 7am in New York.
    expect(latestAwardedWeek(new Date('2026-11-08T12:00:00.000Z'), 'Asia/Taipei')).toBe(
      '2026-11-02',
    );
    expect(latestAwardedWeek(new Date('2026-11-08T12:00:00.000Z'), NEW_YORK)).toBe('2026-10-26');
  });
});

describe('weeksMaybeAwarded', () => {
  it('covers the week due in every zone, and the one before for retries', () => {
    // Sunday noon UTC: 8pm has come in Taipei, not in New York.
    expect(weeksMaybeAwarded(new Date('2026-11-08T12:00:00.000Z'))).toStrictEqual([
      '2026-10-19',
      '2026-10-26',
      '2026-11-02',
    ]);
    // Wednesday: every zone is past last Sunday 8pm.
    expect(weeksMaybeAwarded(new Date('2026-11-11T12:00:00.000Z'))).toStrictEqual([
      '2026-10-26',
      '2026-11-02',
    ]);
  });
});

describe('WeekStart', () => {
  it('takes only a Monday', () => {
    expect(WeekStart.safeParse('2026-10-19').success).toBe(true);
    expect(WeekStart.safeParse('2026-10-20').success).toBe(false);
  });
});
