import { describe, expect, it } from 'vitest';

import { lastTrained, sceneIn, SceneWeek, type Scene, type ScenePick } from './scene.js';

const week = (day: string) => SceneWeek.parse(day);
const pick = (day: string, scene: Scene): ScenePick => ({
  week: week(day),
  scene,
  by: null,
  at: new Date(`${day}T00:00:00Z`),
});

describe('a squad’s scene', () => {
  it('is the gym before any pick, then the latest pick', () => {
    const picks = [pick('2026-10-12', 'pool'), pick('2026-10-26', 'tennis')];
    expect(sceneIn([], week('2026-10-26'))).toBe('gym');
    expect(sceneIn(picks, week('2026-10-05'))).toBe('gym');
    expect(sceneIn(picks, week('2026-10-19'))).toBe('pool');
    expect(sceneIn(picks, week('2026-11-09'))).toBe('tennis');
  });

  it('says how many weeks ago the squad last trained on each scene', () => {
    const picks = [pick('2026-10-12', 'pool'), pick('2026-10-26', 'tennis')];
    const last = lastTrained(picks, { firstWeek: week('2026-09-28'), current: week('2026-11-09') });
    expect(Object.fromEntries(last)).toStrictEqual({
      track: null,
      pool: 3,
      gym: 5,
      tennis: 0,
      climbing: null,
    });
  });

  it('never counts the gym for a squad whose first week was picked', () => {
    const last = lastTrained([pick('2026-10-26', 'pool')], {
      firstWeek: week('2026-10-26'),
      current: week('2026-10-26'),
    });
    expect([last.get('gym'), last.get('pool')]).toStrictEqual([null, 0]);
  });

  it('keeps the latest stint when a scene comes back', () => {
    const picks = [
      pick('2026-10-05', 'pool'),
      pick('2026-10-12', 'gym'),
      pick('2026-10-19', 'pool'),
    ];
    const last = lastTrained(picks, { firstWeek: week('2026-10-05'), current: week('2026-11-02') });
    expect([last.get('pool'), last.get('gym')]).toStrictEqual([0, 3]);
  });
});
