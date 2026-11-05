import { isOpen, takeoverOn, type ListedScene, type SwitchOn } from '../domain/catalog.js';
import type { SceneEdit } from '../domain/edits.js';
import type { SceneStore, SwitchStates } from '../ports.js';

/** The scenes: what the picker shows and which a squad may train on in a week. */
export interface Scenes {
  /** Every scene, retired ones too, in the picker's order. */
  list(): Promise<readonly ListedScene[]>;
  /** The ids of the scenes a squad may train on on `day` (`YYYY-MM-DD`), in the picker's order. */
  openOn(day: string): Promise<readonly string[]>;
  /**
   * The takeover scene every home shows on `day` with the switches as one member sees them
   * (`switchOn`), if one is on.
   */
  takeover(options: {
    readonly day: string;
    readonly switchOn: SwitchOn;
  }): Promise<string | undefined>;
}

/** Changing the scenes, for admins. Each change answers with the list as it now is. */
export interface ScenesAdmin {
  /** Adds a scene, or replaces every field of one, keeping its id. */
  putScene(edit: SceneEdit): Promise<readonly ListedScene[]>;
}

export function createScenes({
  store,
  switches,
}: {
  readonly store: SceneStore;
  readonly switches: SwitchStates;
}): Scenes & ScenesAdmin {
  return {
    list: () => store.list(),
    async openOn(day) {
      const [scenes, switchOn] = await Promise.all([store.list(), switches()]);
      return scenes.filter((scene) => isOpen(scene, { day, switchOn })).map(({ id }) => id);
    },

    takeover: async (options) => takeoverOn(await store.list(), options),

    async putScene({ position, switchId, takeover, ...fields }) {
      const scenes = await store.list();
      const current = scenes.findIndex(({ id }) => id === fields.id);
      const others = scenes.map(({ id }) => id).filter((id) => id !== fields.id);
      const at = Math.min(
        (position ?? (current === -1 ? Infinity : current + 1)) - 1,
        others.length,
      );
      const scene = {
        ...fields,
        ...(switchId === undefined ? {} : { switchId }),
        ...(takeover === true ? { takeover } : {}),
      };
      await store.save(scene, [...others.slice(0, at), fields.id, ...others.slice(at)]);
      return store.list();
    },
  };
}
