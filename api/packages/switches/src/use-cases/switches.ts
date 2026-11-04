import { isOn, type Switch, type SwitchEdit } from '../domain/switches.js';
import type { SwitchStore } from '../ports.js';

/** Whether the switch `id` is on on `day` (`YYYY-MM-DD`, New York); false for one not listed. */
export type SwitchOn = (id: string, day: string) => boolean;

/** The switches, read by whatever follows them. */
export interface Switches {
  list(): Promise<readonly Switch[]>;
  /** Every switch as it is now, as one lookup. */
  states(): Promise<SwitchOn>;
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
    async put({ window, ...fields }) {
      await store.put({ ...fields, ...(window === undefined ? {} : { window }) });
      return store.list();
    },
  };
}
