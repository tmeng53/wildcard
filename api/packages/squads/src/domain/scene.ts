import { z } from 'zod';

import type { MemberId } from './squad.js';

/**
 * A scene a squad trains on, by its id in the scenes list (`@wildcard/scenes`), which says which
 * are open in a week. The app draws each one, and the gym for one it has no art for.
 */
export const Scene = z.string().regex(/^[a-z][A-Za-z0-9]{0,39}$/);
export type Scene = z.infer<typeof Scene>;

/** The scenes a squad may train on in a week, in the picker's order. */
export type OpenScenes = readonly Scene[];

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
 * Each of `scenes` and how many weeks ago the squad last trained on it: 0 for the scene of
 * `current`, null for one it never has. A squad trains on its latest pick until the next one, and
 * on the gym from the week it was made until its first pick.
 */
export function lastTrained(
  picks: readonly ScenePick[],
  {
    firstWeek,
    current,
    scenes,
  }: {
    readonly firstWeek: SceneWeek;
    readonly current: SceneWeek;
    readonly scenes: readonly Scene[];
  },
): Map<Scene, number | null> {
  const stints: { scene: Scene; from: SceneWeek }[] = [{ scene: FIRST_SCENE, from: firstWeek }];
  for (const pick of picks.toSorted((a, b) => a.week.localeCompare(b.week))) {
    if (pick.week > current) break;
    stints.push({ scene: pick.scene, from: pick.week });
  }
  const last = new Map<Scene, number | null>(scenes.map((scene) => [scene, null]));
  stints.forEach(({ scene, from }, index) => {
    const next = stints[index + 1]?.from;
    // A stint that a pick in its own first week replaced was never trained on.
    if (next !== undefined && next <= from) return;
    const until = next === undefined ? current : weekBefore(next);
    const ago = weeksBetween(until, current);
    if (!last.has(scene)) return;
    const before = last.get(scene);
    if (before === null || before === undefined || ago < before) last.set(scene, ago);
  });
  return last;
}

/**
 * The squad's scene in `current`: its latest pick up to then, else the gym. A pick whose scene
 * isn't open in `current` (a winter scene once winter is over, or a retired one) is the gym.
 */
export function sceneIn(
  picks: readonly ScenePick[],
  { current, open }: { readonly current: SceneWeek; readonly open: OpenScenes },
): Scene {
  let latest: ScenePick | undefined;
  for (const pick of picks) {
    if (pick.week <= current && (latest === undefined || pick.week > latest.week)) latest = pick;
  }
  return latest !== undefined && open.includes(latest.scene) ? latest.scene : FIRST_SCENE;
}
