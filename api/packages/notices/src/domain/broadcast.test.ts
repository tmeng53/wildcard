import { describe, expect, it } from 'vitest';

import { Destination } from './broadcast.js';

describe('Destination', () => {
  it('takes every place the app opens, 教练招聘会, 衣橱 and the badge board included', () => {
    for (const place of [
      'stores',
      'store/powder',
      'schedule',
      'squad',
      'coaches',
      'feed',
      'today',
      'me',
      'wardrobe',
      'wardrobe/thanks-bulb',
      'badges',
    ]) {
      expect(Destination.safeParse(place).success).toBe(true);
    }
  });

  it('refuses a place the app has no page for', () => {
    expect(Destination.safeParse('coach').success).toBe(false);
    expect(Destination.safeParse('coaches/xiaohun').success).toBe(false);
    expect(Destination.safeParse('wardrobe/').success).toBe(false);
    expect(Destination.safeParse('badges/idea-king').success).toBe(false);
  });
});
