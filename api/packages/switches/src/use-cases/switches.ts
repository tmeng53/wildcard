import { isOn, wasOn, type Switch, type SwitchEdit } from '../domain/switches.js';
import type { SwitchStore } from '../ports.js';

/** Whether the switch `id` is on on `day` (`YYYY-MM-DD`, New York); false for one not listed. */
export type SwitchOn = (id: string, day: string) => boolean;

/** Whether the switch `id` was on at `at`, on `day` (New York), as it was set then. */
export type SwitchWasOn = (id: string, at: Date, day: string) => boolean;

/** The switches, read by whatever follows them. */
export interface Switches {
  list(): Promise<readonly Switch[]>;
  /** Every switch as it is now, as one lookup. */
  states(): Promise<SwitchOn>;
  /** Every switch as it was set at any time, from its log, as one lookup, for counting the past. */
  history(): Promise<SwitchWasOn>;
}

/** Changing the switches, for admins. Each change answers with the list as it now is. */
export interface SwitchesAdmin {
  put(edit: SwitchEdit): Promise<readonly Switch[]>;
}

export function createSwitches({
  store,
}: {
  readonly store: SwitchStore;
}): Switches & SwitchesAdmin {
  return {
    list: () => store.list(),
    async states() {
      const switches = new Map((await store.list()).map((each) => [each.id, each]));
      return (id, day) => {
        const found = switches.get(id);
        return found !== undefined && isOn(found, day);
      };
    },
    async history() {
      const [settings, current] = await Promise.all([store.history(), store.list()]);
      return wasOn(settings, current);
    },
    async put({ window, ...fields }) {
      await store.put({ ...fields, ...(window === undefined ? {} : { window }) });
      return store.list();
    },
  };
}
