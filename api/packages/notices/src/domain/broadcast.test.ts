import { describe, expect, it } from 'vitest';

import { Destination } from './broadcast.js';

describe('Destination', () => {
  it('takes every place the app opens, 教练招聘会 included', () => {
    for (const place of [
      'stores',
      'store/powder',
      'schedule',
      'squad',
      'coaches',
      'feed',
      'today',
      'me',
    ]) {
      expect(Destination.safeParse(place).success).toBe(true);
    }
  });

  it('refuses a place the app has no page for', () => {
    expect(Destination.safeParse('coach').success).toBe(false);
    expect(Destination.safeParse('coaches/xiaohun').success).toBe(false);
  });
});
