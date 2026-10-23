import { z } from 'zod';

import type { MemberId } from './squad.js';

/** The scenes a squad trains on: the app draws each one. */
export const Scene = z.enum(['track', 'pool', 'gym', 'tennis', 'climbing']);
export type Scene = z.infer<typeof Scene>;

/** Where every squad starts, before anyone picks: the gym, the scene the designs are drawn on. */
export const FIRST_SCENE: Scene = 'gym';

/** A week's Monday, `YYYY-MM-DD`. */
export const SceneWeek = z.iso
  .date()
  .refine((day) => new Date(Date.parse(day)).getUTCDay() === 1, { message: 'Must be a Monday' })
  .brand<'SceneWeek'>();
export type SceneWeek = z.infer<typeof SceneWeek>;

const WEEK = 7 * 86_400_000;

/** How many whole weeks `to` is after `from`. */
export function weeksBetween(from: SceneWeek, to: SceneWeek): number {
  return Math.round((Date.parse(to) - Date.parse(from)) / WEEK);
}

/** The Monday a week before `week`. */
export function weekBefore(week: SceneWeek): SceneWeek {
  return SceneWeek.parse(new Date(Date.parse(week) - WEEK).toISOString().slice(0, 10));
}

/** A squad's pick for one week. `by` is null once the picker deletes their account. */
export interface ScenePick {
  readonly week: SceneWeek;
  readonly scene: Scene;
  readonly by: MemberId | null;
  readonly at: Date;
}

/**
 * Each scene and how many weeks ago the squad last trained on it: 0 for the scene of `current`,
 * null for one it never has. A squad trains on its latest pick until the next one, and on the
 * gym from the week it was made until its first pick.
 */
export function lastTrained(
  picks: readonly ScenePick[],
  { firstWeek, current }: { readonly firstWeek: SceneWeek; readonly current: SceneWeek },
): Map<Scene, number | null> {
  const stints: { scene: Scene; from: SceneWeek }[] = [{ scene: FIRST_SCENE, from: firstWeek }];
  for (const pick of picks.toSorted((a, b) => a.week.localeCompare(b.week))) {
    if (pick.week > current) break;
    stints.push({ scene: pick.scene, from: pick.week });
  }
  const last = new Map<Scene, number | null>(Scene.options.map((scene) => [scene, null]));
  stints.forEach(({ scene, from }, index) => {
    const next = stints[index + 1]?.from;
    // A stint that a pick in its own first week replaced was never trained on.
    if (next !== undefined && next <= from) return;
    const until = next === undefined ? current : weekBefore(next);
    const ago = weeksBetween(until, current);
    const before = last.get(scene);
    if (before === null || before === undefined || ago < before) last.set(scene, ago);
  });
  return last;
}

/** The squad's scene in `current`: its latest pick up to then, else the gym. */
export function sceneIn(picks: readonly ScenePick[], current: SceneWeek): Scene {
  let latest: ScenePick | undefined;
  for (const pick of picks) {
    if (pick.week <= current && (latest === undefined || pick.week > latest.week)) latest = pick;
  }
  return latest?.scene ?? FIRST_SCENE;
}
