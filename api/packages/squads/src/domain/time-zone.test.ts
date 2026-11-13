import { describe, expect, it } from 'vitest';

import { SceneWeek } from './scene.js';
import { weekAt, weekOfChange, zoneAt, zoneFor, type TimeZoneSetting } from './time-zone.js';

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

  it('starts a week on its own zone’s clock, whatever the week before kept', () => {
    const east = [
      setting('2026-11-23', 'America/Los_Angeles'),
      setting('2026-11-30', 'Asia/Taipei'),
    ];
    // Monday 02:00 in Taipei, Sunday 10:00 in Los Angeles: 11-30 has begun on Taipei's clock.
    expect(weekAt(east, new Date('2026-11-29T18:00:00Z'))).toBe('2026-11-30');
    expect(zoneAt(east, new Date('2026-11-29T18:00:00Z'))).toBe('Asia/Taipei');
    // Sunday 23:00 in Taipei.
    expect(weekAt(east, new Date('2026-11-29T15:00:00Z'))).toBe('2026-11-23');
    expect(zoneAt(east, new Date('2026-11-29T15:00:00Z'))).toBe('America/Los_Angeles');
  });
});

describe('the week a captain’s change counts from', () => {
  const losAngeles = [setting('2026-11-02', 'America/Los_Angeles')];
  const taipei = [setting('2026-11-02', 'Asia/Taipei')];
  const newYork = [setting('2026-10-26', 'America/New_York')];

  it('is the squad’s week, mid-week', () => {
    // Wednesday 2026-11-04 04:00 in Los Angeles, 20:00 in Taipei.
    const moment = new Date('2026-11-04T12:00:00Z');
    expect(weekOfChange(losAngeles, { zone: 'Asia/Taipei', moment })).toBe('2026-11-02');
    expect(weekOfChange(taipei, { zone: 'America/Los_Angeles', moment })).toBe('2026-11-02');
  });

  it('is the next week on a Sunday evening when the new clock’s 8pm has passed', () => {
    // Sunday 2026-11-08 19:00 in Los Angeles is Monday 11:00 in Taipei, past Taipei's Sunday 8pm.
    const moment = new Date('2026-11-09T03:00:00Z');
    expect(weekOfChange(losAngeles, { zone: 'Asia/Taipei', moment })).toBe('2026-11-09');
  });

  it('is the next week from the new clock’s Sunday 8pm on, not a millisecond before', () => {
    // Sunday 2026-11-08 20:00 in Taipei, 04:00 in Los Angeles.
    const freeze = new Date('2026-11-08T12:00:00Z');
    const before = new Date('2026-11-08T11:59:59.999Z');
    expect(weekOfChange(losAngeles, { zone: 'Asia/Taipei', moment: freeze })).toBe('2026-11-09');
    expect(weekOfChange(losAngeles, { zone: 'Asia/Taipei', moment: before })).toBe('2026-11-02');
  });

  it('is the next week once the old clock’s Sunday 8pm has passed, so a frozen 战报 stays frozen', () => {
    // Sunday 2026-11-08 21:00 in Taipei, where the week froze an hour ago, is 05:00 in Los Angeles.
    const moment = new Date('2026-11-08T13:00:00Z');
    expect(weekOfChange(taipei, { zone: 'America/Los_Angeles', moment })).toBe('2026-11-09');
    // From Taipei's 8pm on, not a millisecond before.
    const freeze = new Date('2026-11-08T12:00:00Z');
    const before = new Date('2026-11-08T11:59:59.999Z');
    expect(weekOfChange(taipei, { zone: 'America/Los_Angeles', moment: freeze })).toBe(
      '2026-11-09',
    );
    expect(weekOfChange(taipei, { zone: 'America/Los_Angeles', moment: before })).toBe(
      '2026-11-02',
    );
    // Monday 2026-11-09 02:00 in Taipei is still Sunday 10:00 in Los Angeles: the week before
    // froze on Taipei's clock, so the change waits for the week after it.
    const monday = new Date('2026-11-08T18:00:00Z');
    expect(weekOfChange(taipei, { zone: 'America/Los_Angeles', moment: monday })).toBe(
      '2026-11-09',
    );
  });

  it('is the week before when a change waiting for next week is undone before either 8pm', () => {
    // Los Angeles this week, Taipei waiting for the next. Monday 2026-11-09 01:00 in Taipei, so
    // the squad is in its next week, is Sunday 09:00 in Los Angeles, where 11-02 hasn't frozen.
    const waiting = [...losAngeles, setting('2026-11-09', 'Asia/Taipei')];
    const moment = new Date('2026-11-08T17:00:00Z');
    expect(weekOfChange(waiting, { zone: 'America/Los_Angeles', moment })).toBe('2026-11-02');
  });

  it('follows the clocks going back, New York’s 8pm that Sunday being 01:00 UTC', () => {
    // The week of 2026-10-26 freezes in New York at 2026-11-02T01:00Z, after DST ends at 2am.
    const freeze = new Date('2026-11-02T01:00:00Z');
    const before = new Date('2026-11-02T00:59:59.999Z');
    // New York the old clock.
    expect(weekOfChange(newYork, { zone: 'America/Los_Angeles', moment: freeze })).toBe(
      '2026-11-02',
    );
    expect(weekOfChange(newYork, { zone: 'America/Los_Angeles', moment: before })).toBe(
      '2026-10-26',
    );
    // New York the new clock.
    const fromLosAngeles = [setting('2026-10-26', 'America/Los_Angeles')];
    expect(weekOfChange(fromLosAngeles, { zone: 'America/New_York', moment: freeze })).toBe(
      '2026-11-02',
    );
    expect(weekOfChange(fromLosAngeles, { zone: 'America/New_York', moment: before })).toBe(
      '2026-10-26',
    );
  });
});
