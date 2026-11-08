import { describe, expect, it } from 'vitest';

import { sceneWeekAt } from './squad-scene.js';

describe('the week a squad picks its scene for', () => {
  // On Los Angeles for the week of 11-23, then Taipei from 11-30.
  const zoneOf = (week: string) => (week >= '2026-11-30' ? 'Asia/Taipei' : 'America/Los_Angeles');

  it('waits for a week’s own Sunday 8pm when the squad moves east', () => {
    // Monday 02:00 in Taipei, still Sunday morning in Los Angeles: the 11-23 week isn't awarded.
    expect(sceneWeekAt(new Date('2026-11-29T18:00:00Z'), zoneOf)).toBe('2026-11-23');
    // Sunday 20:00 in Los Angeles.
    expect(sceneWeekAt(new Date('2026-11-30T04:00:00Z'), zoneOf)).toBe('2026-11-30');
  });

  it('opens next week once the week’s 8pm passes on its clock', () => {
    // Sunday 2026-12-06 20:00 in Taipei.
    expect(sceneWeekAt(new Date('2026-12-06T11:59:00Z'), zoneOf)).toBe('2026-11-30');
    expect(sceneWeekAt(new Date('2026-12-06T12:00:00Z'), zoneOf)).toBe('2026-12-07');
  });
});
