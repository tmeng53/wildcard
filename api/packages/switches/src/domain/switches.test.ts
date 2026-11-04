import { describe, expect, it } from 'vitest';

import { inWindow, isOn, SwitchEdit, type Switch } from './switches.js';

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
