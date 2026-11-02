import { CoachSettings, type CoachSettingsChange, type MemberId } from '../domain/settings.js';
import type { CoachSettingsStore } from '../ports.js';

/** What every coach runs with, for the admins to read and change. */
export interface CoachSettingsAdmin {
  current(): Promise<CoachSettings>;
  /**
   * Applies `change` to the current settings and saves them, logged as `by`'s change; nothing is
   * saved or logged when it changes nothing. Returns the settings now.
   */
  change(change: CoachSettingsChange, by: MemberId): Promise<CoachSettings>;
}

export function createCoachSettings(deps: {
  readonly store: CoachSettingsStore;
}): CoachSettingsAdmin {
  return {
    current: () => deps.store.current(),
    change: async (change, by) => {
      const settings = CoachSettings.parse({
        ...(await deps.store.current({ forUpdate: true })),
        ...change,
      });
      await deps.store.save(settings, by);
      return settings;
    },
  };
}
