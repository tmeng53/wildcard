import { describe, expect, it } from 'vitest';

import { inWindow, isOpen, type ListedScene } from './catalog.js';

const winter = { start: '11-15', end: '03-31' };

describe('a scene’s window', () => {
  it('is open all year without one', () => {
    expect(inWindow(undefined, '2026-07-01')).toBe(true);
  });

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

  it('keeps a retired scene closed whatever the day', () => {
    const scene: ListedScene = {
      id: 'ski',
      names: { zhHans: '雪场', en: 'Ski', zhHant: '雪場' },
      colors: {
        signature: '#16384D',
        onSignature: '#D6F1FB',
        wash: '#EAF7FD',
        text: '#16384D',
        floor: '#D7ECF6',
      },
      offered: false,
      window: winter,
    };
    expect(isOpen(scene, '2026-12-01')).toBe(false);
    expect(isOpen({ ...scene, offered: true }, '2026-12-01')).toBe(true);
  });
});
