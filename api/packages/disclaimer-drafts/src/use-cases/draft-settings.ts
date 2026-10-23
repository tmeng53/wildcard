import {
  DraftSettings,
  type DraftSettings as Settings,
  type DraftSettingsChange,
} from '../domain/settings.js';
import type { MemberId } from '../domain/draft-request.js';
import type { DraftSettingsStore } from '../ports.js';

/** What drafts are written with, for the admins to read and change. */
export interface DraftSettingsAdmin {
  current(): Promise<Settings>;
  /**
   * Applies `change` to the current settings and saves them, logged as `by`'s change; nothing is
   * saved or logged when it changes nothing. Returns the settings now.
   */
  change(change: DraftSettingsChange, by: MemberId): Promise<Settings>;
}

export function createDraftSettings(deps: {
  readonly store: DraftSettingsStore;
}): DraftSettingsAdmin {
  return {
    current: () => deps.store.current(),
    change: async (change, by) => {
      const settings = DraftSettings.parse({ ...(await deps.store.current()), ...change });
      await deps.store.save(settings, by);
      return settings;
    },
  };
}
