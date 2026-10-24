import {
  DailyPushSettings,
  type DailyPushSettings as Settings,
  type DailyPushSettingsChange,
} from '../domain/daily-push-settings.js';
import type { MemberId } from '../domain/device.js';
import type { DailyPushSettingsStore } from '../ports.js';

/** The daily push's settings for everyone, for the admins to read and change. */
export interface DailyPushSettingsAdmin {
  current(): Promise<Settings>;
  /**
   * Applies `change` to the current settings and saves them, logged as `by`'s change; nothing is
   * saved or logged when it changes nothing. Returns the settings now.
   */
  change(change: DailyPushSettingsChange, by: MemberId): Promise<Settings>;
}

export function createDailyPushSettings(deps: {
  readonly store: DailyPushSettingsStore;
}): DailyPushSettingsAdmin {
  return {
    current: () => deps.store.current(),
    change: async (change, by) => {
      const settings = DailyPushSettings.parse({
        ...(await deps.store.current({ forUpdate: true })),
        ...change,
      });
      await deps.store.save(settings, by);
      return settings;
    },
  };
}
