import { describe, expect, it } from 'vitest';

import {
  coachNotesOn,
  inWindow,
  isOn,
  isOnForPreviewer,
  SwitchEdit,
  wasOn,
  type Switch,
} from './switches.js';

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

  it('in preview, is on only for previewers, in its window', () => {
    const preview: Switch = { ...scheduled, mode: 'preview' };
    expect(isOn(preview, '2026-12-01')).toBe(false);
    expect(isOnForPreviewer(preview, '2026-12-01')).toBe(true);
    expect(isOnForPreviewer(preview, '2026-07-01')).toBe(false);
    expect(isOnForPreviewer(scheduled, '2026-12-01')).toBe(true);
  });

  it('needs a window to follow a schedule', () => {
    expect(SwitchEdit.safeParse({ id: 'winter', label: 'Winter', mode: 'schedule' }).success).toBe(
      false,
    );
    expect(SwitchEdit.safeParse({ id: 'winter', label: 'Winter', mode: 'off' }).success).toBe(true);
  });
});

describe('the coach’s notes', () => {
  const thanksgiving: Switch = {
    id: 'thanksgivingDay',
    label: 'Thanksgiving day',
    mode: 'schedule',
    window: { start: '11-26', end: '11-26' },
    coachNote: '今天是感恩节',
  };
  const store: Switch = {
    id: 'thanksgiving',
    label: 'TURKEY TROT',
    mode: 'schedule',
    window: { start: '11-24', end: '11-26' },
    coachNote: 'TURKEY TROT 开张了',
  };
  const winterSwitch: Switch = { id: 'winter', label: 'Winter', mode: 'schedule', window: winter };

  it('are those of the switches on that day, for everyone', () => {
    const all = [thanksgiving, store, winterSwitch];
    expect(coachNotesOn(all, '2026-11-23')).toStrictEqual([]);
    expect(coachNotesOn(all, '2026-11-24')).toStrictEqual(['TURKEY TROT 开张了']);
    expect(coachNotesOn(all, '2026-11-26')).toStrictEqual(['今天是感恩节', 'TURKEY TROT 开张了']);
    // A switch in preview tells the coach nothing: every squad's coach would hear of it.
    expect(coachNotesOn([{ ...thanksgiving, mode: 'preview' }], '2026-11-26')).toStrictEqual([]);
  });

  it('are short lines, never empty', () => {
    const edit = { id: 'winter', label: 'Winter', mode: 'off' };
    expect(SwitchEdit.safeParse({ ...edit, coachNote: '  ' }).success).toBe(false);
    expect(SwitchEdit.safeParse({ ...edit, coachNote: '雪'.repeat(121) }).success).toBe(false);
    expect(SwitchEdit.parse({ ...edit, coachNote: ' 下雪了 ' }).coachNote).toBe('下雪了');
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
