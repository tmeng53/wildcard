import { describe, expect, it } from 'vitest';

import { isOpen, type ListedScene } from './catalog.js';

const ski: ListedScene = {
  id: 'ski',
  names: { zhHans: '雪场', en: 'Ski', zhHant: '雪場' },
  colors: {
    signature: '#16384D',
    onSignature: '#D6F1FB',
    wash: '#EAF7FD',
    text: '#16384D',
    floor: '#D7ECF6',
  },
  offered: true,
  switchId: 'winter',
};
const winterOn = (id: string, day: string) => id === 'winter' && day >= '2026-11-15';

describe('a scene’s switch', () => {
  it('opens a limited scene only while its switch is on', () => {
    expect(isOpen(ski, { day: '2026-11-14', switchOn: winterOn })).toBe(false);
    expect(isOpen(ski, { day: '2026-12-01', switchOn: winterOn })).toBe(true);
  });

  it('keeps a scene without a switch open all year', () => {
    const gym = { ...ski, id: 'gym', switchId: undefined };
    expect(isOpen(gym, { day: '2026-07-01', switchOn: () => false })).toBe(true);
  });

  it('keeps a retired scene closed whatever the day', () => {
    expect(isOpen({ ...ski, offered: false }, { day: '2026-12-01', switchOn: winterOn })).toBe(
      false,
    );
  });
});
