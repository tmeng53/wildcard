import { describe, expect, it } from 'vitest';

import { inWindow, isOn, SwitchEdit, wasOn, type Switch } from './switches.js';

const winter = { start: '11-15', end: '03-31' };

describe('a window', () => {
  it('runs over New Year, both ends included', () => {
    expect(inWindow(winter, '2026-11-14')).toBe(false);
    expect(inWindow(winter, '2026-11-15')).toBe(true);
    expect(inWindow(winter, '2026-12-31')).toBe(true);
    expect(inWindow(winter, '2027-01-01')).toBe(true);
    expect(inWindow(winter, '2027-03-31')).toBe(true);
    expect(inWindow(winter, '2027-04-01')).toBe(false);
  });

  it('works within one year too', () => {
    const summer = { start: '06-01', end: '08-31' };
    expect(inWindow(summer, '2026-05-31')).toBe(false);
    expect(inWindow(summer, '2026-06-01')).toBe(true);
    expect(inWindow(summer, '2026-08-31')).toBe(true);
    expect(inWindow(summer, '2026-09-01')).toBe(false);
  });
});

describe('a switch', () => {
  const scheduled: Switch = { id: 'winter', label: 'Winter', mode: 'schedule', window: winter };

  it('follows its schedule every year', () => {
    expect(isOn(scheduled, '2026-11-14')).toBe(false);
    expect(isOn(scheduled, '2026-11-15')).toBe(true);
    expect(isOn(scheduled, '2027-11-20')).toBe(true);
  });

  it('is on or off by hand whatever the day', () => {
    expect(isOn({ ...scheduled, mode: 'on' }, '2026-07-01')).toBe(true);
    expect(isOn({ ...scheduled, mode: 'off' }, '2026-12-01')).toBe(false);
  });

  it('needs a window to follow a schedule', () => {
    expect(SwitchEdit.safeParse({ id: 'winter', label: 'Winter', mode: 'schedule' }).success).toBe(
      false,
    );
    expect(SwitchEdit.safeParse({ id: 'winter', label: 'Winter', mode: 'off' }).success).toBe(true);
  });
});

describe('a switch as it was set', () => {
  const scheduled: Switch = { id: 'winter', label: 'Winter', mode: 'schedule', window: winter };
  const history = [
    { at: new Date('2026-11-01T00:00:00Z'), value: scheduled },
    // Closed early by hand in mid-December.
    { at: new Date('2026-12-15T00:00:00Z'), value: { ...scheduled, mode: 'off' as const } },
  ];
  const was = wasOn(history, [{ ...scheduled, mode: 'off' }]);

  it('counts what came before a change by hand as it was set then', () => {
    expect(was('winter', { at: new Date('2026-11-20T12:00:00Z'), day: '2026-11-20' })).toBe(true);
    expect(was('winter', { at: new Date('2026-12-16T12:00:00Z'), day: '2026-12-16' })).toBe(false);
  });

  it('counts before its first change as its first setting, and with no log as it is now', () => {
    expect(was('winter', { at: new Date('2026-01-10T12:00:00Z'), day: '2026-01-10' })).toBe(true);
    expect(was('summer', { at: new Date('2026-07-10T12:00:00Z'), day: '2026-07-10' })).toBe(false);
    const unlogged = wasOn([], [{ id: 'summer', label: 'Summer', mode: 'on' }]);
    expect(unlogged('summer', { at: new Date('2026-07-10T12:00:00Z'), day: '2026-07-10' })).toBe(
      true,
    );
  });
});
