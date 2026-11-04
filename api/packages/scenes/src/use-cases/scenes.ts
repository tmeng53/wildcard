import { isOpen, type ListedScene } from '../domain/catalog.js';
import type { SceneEdit, SceneWindowEdit } from '../domain/edits.js';
import { SceneNotFoundError } from '../errors.js';
import type { SceneStore } from '../ports.js';

/** The scenes: what the picker shows and which a squad may train on in a week. */
export interface Scenes {
  /** Every scene, retired ones too, in the picker's order. */
  list(): Promise<readonly ListedScene[]>;
  /** The ids of the scenes a squad may train on on `day` (`YYYY-MM-DD`), in the picker's order. */
  openOn(day: string): Promise<readonly string[]>;
}

/** Changing the scenes, for admins. Each change answers with the list as it now is. */
export interface ScenesAdmin {
  /** Adds a scene, or replaces every field of one, keeping its id. */
  putScene(edit: SceneEdit): Promise<readonly ListedScene[]>;
  /** Changes only when a scene is open. */
  setWindow(edit: SceneWindowEdit): Promise<readonly ListedScene[]>;
}

export function createScenes({ store }: { readonly store: SceneStore }): Scenes & ScenesAdmin {
  return {
    list: () => store.list(),
    async openOn(day) {
      return (await store.list()).filter((scene) => isOpen(scene, day)).map(({ id }) => id);
    },

    async putScene({ position, window, ...fields }) {
      const scenes = await store.list();
      const current = scenes.findIndex(({ id }) => id === fields.id);
      const others = scenes.map(({ id }) => id).filter((id) => id !== fields.id);
      const at = Math.min(
        (position ?? (current === -1 ? Infinity : current + 1)) - 1,
        others.length,
      );
      await store.save({ ...fields, ...(window === undefined ? {} : { window }) }, [
        ...others.slice(0, at),
        fields.id,
        ...others.slice(at),
      ]);
      return store.list();
    },

    async setWindow({ id, window }) {
      const scenes = await store.list();
      const scene = scenes.find((each) => each.id === id);
      if (scene === undefined) throw new SceneNotFoundError(id);
      const { id: kept, names, colors, offered } = scene;
      await store.save(
        { id: kept, names, colors, offered, ...(window === null ? {} : { window }) },
        scenes.map((each) => each.id),
      );
      return store.list();
    },
  };
}
