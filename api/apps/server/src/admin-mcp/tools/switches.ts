import { SwitchEdit, type Switch, type Switches, type SwitchesAdmin } from '@wildcard/switches';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// Global switches: one turns many things on or off together (the winter switch opens the 雪场
// scene and lets POWDER DAY's pieces unlock). A scene or unlock rule names the switch it follows.
// A change reaches apps through the public catalog within a minute. Switches are never deleted.

interface SwitchToolDependencies {
  readonly switches: Switches & SwitchesAdmin;
}

const shown = (switches: readonly Switch[]) => ({ version: 1, switches: [...switches] });

/** `get_switches`: every switch now. */
export function getSwitches({ switches }: SwitchToolDependencies) {
  return adminTool({
    name: 'get_switches',
    title: 'Read the switches',
    description:
      'Shows every global switch: id, label, mode (on, off, or schedule) and, for a schedule, ' +
      'window (MM-DD to MM-DD every year, both included, New York time; the end may come before ' +
      'the start, over New Year). Scenes and unlock rules with this switchId follow it.',
    changes: false,
    input: z.strictObject({}),
    run: async () => shown(await switches.list()),
  });
}

/** `put_switch`: adds a switch, or replaces one whole. */
export function putSwitch({ switches }: SwitchToolDependencies) {
  return adminTool({
    name: 'put_switch',
    title: 'Add or change a switch',
    description:
      'Adds a switch, or replaces every field of one (read it with get_switches first). mode on ' +
      'or off holds until changed; schedule needs a window and turns on every year in it. ' +
      'Everything with this switchId follows at once: a limited scene opens or closes (a squad on ' +
      'it goes back to the gym the next week) and its unlock rules count 练了 only while it is ' +
      'on. Pieces members unlocked are kept. Apps see it within a minute. Returns the switches now.',
    changes: true,
    input: SwitchEdit,
    run: async (edit) => shown(await switches.put(edit)),
  });
}

export const switchTools = (deps: SwitchToolDependencies) => [getSwitches(deps), putSwitch(deps)];
