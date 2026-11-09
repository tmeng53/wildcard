import {
  isOn,
  isOnForPreviewer,
  wasOn,
  type Switch,
  type SwitchEdit,
  type SwitchView,
} from '../domain/switches.js';
import type { SwitchStore } from '../ports.js';

/** Whether the switch `id` is on on `day` (`YYYY-MM-DD`, New York); false for one not listed. */
export type SwitchOn = (id: string, day: string) => boolean;

/** Whether the switch `id` was on at `at`, on `day` (New York), as it was set then. */
export type SwitchWasOn = (
  id: string,
  when: { readonly at: Date; readonly day: string },
) => boolean;
/** The switches as one member sees them. */
export interface MemberSwitches {
  /** Whether a switch is on on a (real) New York `day`, shifted by the member's pretend days. */
  readonly on: SwitchOn;
}

/** The switches, read by whatever follows them. */
export interface Switches {
  list(): Promise<readonly Switch[]>;
  /** Every switch as everyone who doesn't preview sees it now, as one lookup. */
  states(): Promise<SwitchOn>;
  /**
   * Every switch as `member` saw it at any time, for counting the past: as each was set then, from
   * its log; for a previewer, as they see the switches now (one in preview on, on their day).
   */
  historyFor(member: string): Promise<SwitchWasOn>;
  /**
   * For a previewer, every switch as it really was set at any time, from its log, which is what
   * what they keep counts under; undefined for a member who doesn't preview.
   */
  keptHistoryFor(member: string): Promise<SwitchWasOn | undefined>;
  /** Every switch as `member` sees it: a switch in preview is on for a previewer, on their day. */
  statesFor(member: string): Promise<MemberSwitches>;
}

/** Changing the switches, for admins. Each change answers with the list as it now is. */
export interface SwitchesAdmin {
  put(edit: SwitchEdit): Promise<readonly Switch[]>;
  /** Sets who previews switches and the day they pretend it is; answers with every previewer. */
  setView(change: {
    readonly member: string;
    readonly view: SwitchView;
    readonly by: string;
  }): Promise<readonly { readonly member: string; readonly dayOffset: number }[]>;
  previewers(): Promise<readonly { readonly member: string; readonly dayOffset: number }[]>;
}

const DAY = 86_400_000;

/** `day` (`YYYY-MM-DD`) moved by `offset` days. */
export function addDays(day: string, offset: number): string {
  if (offset === 0) return day;
  return new Date(Date.parse(`${day}T12:00:00Z`) + offset * DAY).toISOString().slice(0, 10);
}

export function createSwitches({
  store,
}: {
  readonly store: SwitchStore;
}): Switches & SwitchesAdmin {
  const lookup = async (view: SwitchView): Promise<SwitchOn> => {
    const switches = new Map((await store.list()).map((each) => [each.id, each]));
    return (id, day) => {
      const found = switches.get(id);
      if (found === undefined) return false;
      const seen = addDays(day, view.dayOffset);
      return view.previewer ? isOnForPreviewer(found, seen) : isOn(found, seen);
    };
  };
  const history = async () => {
    const [settings, current] = await Promise.all([store.history(), store.list()]);
    return wasOn(settings, current);
  };
  return {
    list: () => store.list(),
    states: () => lookup({ previewer: false, dayOffset: 0 }),
    async statesFor(member) {
      const view = await store.viewOf(member);
      return { on: await lookup(view) };
    },
    async historyFor(member) {
      const view = await store.viewOf(member);
      if (view.previewer || view.dayOffset !== 0) {
        const on = await lookup(view);
        return (id, { day }) => on(id, day);
      }
      return history();
    },
    async keptHistoryFor(member) {
      const view = await store.viewOf(member);
      return view.previewer || view.dayOffset !== 0 ? history() : undefined;
    },
    async put({ window, ...fields }) {
      await store.put({ ...fields, ...(window === undefined ? {} : { window }) });
      return store.list();
    },
    async setView(change) {
      await store.setView(change);
      return store.previewers();
    },
    previewers: () => store.previewers(),
  };
}
