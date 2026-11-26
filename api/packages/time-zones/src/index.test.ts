import { describe, expect, it } from 'vitest';

import {
  TimeZone,
  challengeDay,
  isKnownTimeZone,
  mondayOf,
  momentAt,
  wallClockAt,
  weekFreezesAt,
} from './index.js';

describe('time zones', () => {
  it('reads a moment on a zone’s wall clock', () => {
    const moment = new Date('2026-11-08T01:30:00Z');
    expect(wallClockAt(moment, 'America/New_York')).toEqual({
      day: '2026-11-07',
      hour: 20,
      minute: 30,
    });
    expect(wallClockAt(moment, 'Asia/Taipei')).toEqual({ day: '2026-11-08', hour: 9, minute: 30 });
    expect(wallClockAt(moment, 'America/Los_Angeles')).toEqual({
      day: '2026-11-07',
      hour: 17,
      minute: 30,
    });
    expect(wallClockAt(moment, 'Asia/Kolkata')).toEqual({ day: '2026-11-08', hour: 7, minute: 0 });
  });

  it('finds the moment a wall clock shows an hour, daylight saving or not', () => {
    expect(momentAt({ day: '2026-11-08', hour: 20, zone: 'America/New_York' })).toEqual(
      new Date('2026-11-09T01:00:00Z'),
    );
    expect(momentAt({ day: '2026-10-25', hour: 20, zone: 'America/New_York' })).toEqual(
      new Date('2026-10-26T00:00:00Z'),
    );
    expect(momentAt({ day: '2026-11-08', hour: 20, zone: 'Asia/Taipei' })).toEqual(
      new Date('2026-11-08T12:00:00Z'),
    );
    // The Sunday daylight saving ends on, after the change.
    expect(momentAt({ day: '2026-11-01', hour: 20, zone: 'America/Los_Angeles' })).toEqual(
      new Date('2026-11-02T04:00:00Z'),
    );
  });

  it('knows a real zone and refuses a made-up one', () => {
    expect(isKnownTimeZone('Asia/Taipei')).toBe(true);
    expect(isKnownTimeZone('Mars/Olympus')).toBe(false);
    expect(TimeZone.safeParse('Asia/Taipei').success).toBe(true);
    expect(TimeZone.safeParse('+08:00').success).toBe(false);
  });

  it('starts weeks on Monday', () => {
    expect(mondayOf('2026-11-08')).toBe('2026-11-02');
    expect(mondayOf('2026-11-09')).toBe('2026-11-09');
  });

  it('freezes a week on its Sunday at 8pm on the zone’s clock', () => {
    expect(weekFreezesAt('2026-11-02', 'Asia/Taipei').toISOString()).toBe(
      '2026-11-08T12:00:00.000Z',
    );
    expect(weekFreezesAt('2026-11-02', 'America/Los_Angeles').toISOString()).toBe(
      '2026-11-09T04:00:00.000Z',
    );
    // New York's clocks go back at 2am that Sunday, so its 8pm is 01:00 UTC, not 00:00.
    expect(weekFreezesAt('2026-10-26', 'America/New_York').toISOString()).toBe(
      '2026-11-02T01:00:00.000Z',
    );
  });
});

describe('challengeDay', () => {
  const at = (iso: string) => new Date(iso);

  it('goes by the squad’s day for a member with no zone saved', () => {
    // 01:00 on the 20th in Toronto.
    expect(challengeDay(at('2026-11-20T06:00:00Z'), { squad: 'America/Toronto' })).toBe(
      '2026-11-20',
    );
  });

  it('keeps a member behind the squad on their own day until their midnight', () => {
    const vancouver = { squad: 'America/Toronto', own: 'America/Vancouver' };
    // 22:00 on the 19th in Vancouver, already 01:00 on the 20th in Toronto.
    expect(challengeDay(at('2026-11-20T06:00:00Z'), vancouver)).toBe('2026-11-19');
    // 00:30 on the 20th in Vancouver.
    expect(challengeDay(at('2026-11-20T08:30:00Z'), vancouver)).toBe('2026-11-20');
  });

  it('keeps a member ahead of the squad on the squad’s day until the squad’s midnight', () => {
    const shanghai = { squad: 'America/Toronto', own: 'Asia/Shanghai' };
    // 08:00 on the 21st in Shanghai, still 19:00 on the 20th in Toronto.
    expect(challengeDay(at('2026-11-21T00:00:00Z'), shanghai)).toBe('2026-11-20');
    // 13:30 on the 21st in Shanghai, 00:30 on the 21st in Toronto.
    expect(challengeDay(at('2026-11-21T05:30:00Z'), shanghai)).toBe('2026-11-21');
  });
});
