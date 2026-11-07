import { describe, expect, it } from 'vitest';

import { SceneWeek } from './scene.js';
import { zoneAt, zoneFor, type TimeZoneSetting } from './time-zone.js';

const setting = (week: string, timeZone: string): TimeZoneSetting => ({
  week: SceneWeek.parse(week),
  timeZone,
  by: null,
  at: new Date(0),
});

describe('a squad’s time zone', () => {
  const settings = [
    setting('2026-11-02', 'America/Los_Angeles'),
    setting('2026-11-09', 'Asia/Taipei'),
  ];

  it('is New York before any setting', () => {
    expect(zoneFor([], SceneWeek.parse('2026-11-02'))).toBe('America/New_York');
    expect(zoneFor(settings, SceneWeek.parse('2026-10-26'))).toBe('America/New_York');
  });

  it('is the newest setting from that week or before', () => {
    expect(zoneFor(settings, SceneWeek.parse('2026-11-02'))).toBe('America/Los_Angeles');
    expect(zoneFor(settings, SceneWeek.parse('2026-11-16'))).toBe('Asia/Taipei');
  });

  it('changes at a moment once its week begins on its own clock', () => {
    // Monday 2026-11-09 00:30 in Taipei is still Sunday in Los Angeles.
    expect(zoneAt(settings, new Date('2026-11-08T16:30:00Z'))).toBe('Asia/Taipei');
    expect(zoneAt(settings, new Date('2026-11-08T15:30:00Z'))).toBe('America/Los_Angeles');
    expect(zoneAt(settings, new Date('2026-10-30T12:00:00Z'))).toBe('America/New_York');
  });
});
