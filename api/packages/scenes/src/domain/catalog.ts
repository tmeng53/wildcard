import { z } from 'zod';

// The scenes a squad trains on, as the database keeps them (supabase/migrations, `scenes`):
// data, so a new name, colour, order or switch needs no app release. The art ships with
// the app, which shows the gym for a scene it has no art for.

/** A scene's id, camelCase, as the app and the API know it. Never changes. */
export const SceneId = z.string().regex(/^[a-z][A-Za-z0-9]{0,39}$/);
export type SceneId = z.infer<typeof SceneId>;

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

export interface ListedScene {
  readonly id: SceneId;
  readonly names: LocalizedNames;
  readonly colors: SceneColors;
  /** False for a scene the picker no longer offers. */
  readonly offered: boolean;
  /** The switch a limited scene follows (a squad may pick it only while that is on); none for all year. */
  readonly switchId?: string;
  /**
   * True for a takeover scene: while its switch is on, every squad's home shows it in place of
   * the squad's pick, and the picker never offers it.
   */
  readonly takeover?: boolean;
}

/** Whether the switch `id` is on on `day` (`YYYY-MM-DD`, New York). */
export type SwitchOn = (id: string, day: string) => boolean;

/** Whether a squad may train on `scene` on `day`: offered, and its switch (if any) on then. */
export function isOpen(
  scene: ListedScene,
  { day, switchOn }: { readonly day: string; readonly switchOn: SwitchOn },
): boolean {
  return (
    scene.offered &&
    scene.takeover !== true &&
    (scene.switchId === undefined || switchOn(scene.switchId, day))
  );
}

/** The scene taking over every home on `day`: the first takeover whose switch is on, if any. */
export function takeoverOn(
  scenes: readonly ListedScene[],
  { day, switchOn }: { readonly day: string; readonly switchOn: SwitchOn },
): string | undefined {
  return scenes.find(
    (scene) =>
      scene.takeover === true &&
      scene.offered &&
      scene.switchId !== undefined &&
      switchOn(scene.switchId, day),
  )?.id;
}
