import { z } from 'zod';

// The scenes a squad trains on, as the database keeps them (supabase/migrations, `scenes`):
// data, so a new name, colour, order or open window needs no app release. The art ships with
// the app, which shows the gym for a scene it has no art for.

/** A scene's id, camelCase, as the app and the API know it. Never changes. */
export const SceneId = z.string().regex(/^[a-z][A-Za-z0-9]{0,39}$/);
export type SceneId = z.infer<typeof SceneId>;

/** A day of the year, `MM-DD`. */
export const MonthDay = z.string().regex(/^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/);
export type MonthDay = z.infer<typeof MonthDay>;

/** A colour, `#RRGGBB`. */
export const Hex = z.string().regex(/^#[0-9A-F]{6}$/);

/** A name in each of the app's languages. */
export interface LocalizedNames {
  readonly zhHans: string;
  readonly en: string;
  readonly zhHant: string;
}

/** A scene's colours. */
export interface SceneColors {
  /** The 打卡 button, the week's icons, the poster. */
  readonly signature: string;
  /** Text and symbols drawn on the signature. */
  readonly onSignature: string;
  /** Its light ground. */
  readonly wash: string;
  /** Its colour for text on light grounds. */
  readonly text: string;
  readonly floor: string;
}

/** The days of the year a limited scene is open, both included, every year. */
export interface SceneWindow {
  readonly start: MonthDay;
  readonly end: MonthDay;
}

export interface ListedScene {
  readonly id: SceneId;
  readonly names: LocalizedNames;
  readonly colors: SceneColors;
  /** False for a scene the picker no longer offers. */
  readonly offered: boolean;
  /** When the scene is open; none for all year. */
  readonly window?: SceneWindow;
}

/**
 * Whether `day` (`YYYY-MM-DD`) is in `window`. A window may run over New Year (11-15 to 03-31).
 */
export function inWindow(window: SceneWindow | undefined, day: string): boolean {
  if (window === undefined) return true;
  const md = day.slice(5, 10);
  return window.start <= window.end
    ? window.start <= md && md <= window.end
    : md >= window.start || md <= window.end;
}

/** Whether a squad may train on `scene` on `day`: offered, and open then. */
export function isOpen(scene: ListedScene, day: string): boolean {
  return scene.offered && inWindow(scene.window, day);
}
