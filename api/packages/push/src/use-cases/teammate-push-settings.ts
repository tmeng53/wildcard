import type { MemberId } from '../domain/device.js';
import {
  TeammatePushSettings,
  type TeammatePushSettings as Settings,
  type TeammatePushSettingsChange,
} from '../domain/teammate-push-settings.js';
import type { TeammatePushSettingsStore } from '../ports.js';

/** The teammate push's settings for everyone, for the admins to read and change. */
export interface TeammatePushSettingsAdmin {
  current(): Promise<Settings>;
  /**
   * Applies `change` to the current settings and saves them, logged as `by`'s change; nothing is
   * saved or logged when it changes nothing. Returns the settings now.
   */
  change(change: TeammatePushSettingsChange, by: MemberId): Promise<Settings>;
}

export function createTeammatePushSettings(deps: {
  readonly store: TeammatePushSettingsStore;
}): TeammatePushSettingsAdmin {
  return {
    current: () => deps.store.current(),
    change: async (change, by) => {
      const settings = TeammatePushSettings.parse({
        ...(await deps.store.current({ forUpdate: true })),
        ...change,
      });
      await deps.store.save(settings, by);
      return settings;
    },
  };
}
