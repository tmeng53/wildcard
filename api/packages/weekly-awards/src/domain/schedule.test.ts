import { describe, expect, it } from 'vitest';

import { WeekStart, awardsTimeOf, latestAwardedWeek } from './schedule.js';

const week = (day: string) => WeekStart.parse(day);

describe('awardsTimeOf', () => {
  it('is the week’s Sunday at 8pm Eastern, in daylight time and in standard time', () => {
    expect(awardsTimeOf(week('2026-10-19')).toISOString()).toBe('2026-10-26T00:00:00.000Z');
    // Daylight saving ends on Sunday 2026-11-01 at 2am; 8pm that evening is standard time.
    expect(awardsTimeOf(week('2026-10-26')).toISOString()).toBe('2026-11-02T01:00:00.000Z');
    expect(awardsTimeOf(week('2027-01-04')).toISOString()).toBe('2027-01-11T01:00:00.000Z');
    // Daylight saving starts on Sunday 2027-03-14.
    expect(awardsTimeOf(week('2027-03-08')).toISOString()).toBe('2027-03-15T00:00:00.000Z');
  });
});

describe('latestAwardedWeek', () => {
  it('is last week until Sunday 8pm Eastern, then this week', () => {
    // Sunday 7:59pm in New York (4:59pm in Los Angeles).
    expect(latestAwardedWeek(new Date('2026-10-25T23:59:59.000Z'))).toBe('2026-10-12');
    expect(latestAwardedWeek(new Date('2026-10-26T00:00:00.000Z'))).toBe('2026-10-19');
    // Monday morning in New York: still the week that just ended.
    expect(latestAwardedWeek(new Date('2026-10-26T13:00:00.000Z'))).toBe('2026-10-19');
    expect(latestAwardedWeek(new Date('2026-10-31T12:00:00.000Z'))).toBe('2026-10-19');
  });
});

describe('WeekStart', () => {
  it('takes only a Monday', () => {
    expect(WeekStart.safeParse('2026-10-19').success).toBe(true);
    expect(WeekStart.safeParse('2026-10-20').success).toBe(false);
  });
});
