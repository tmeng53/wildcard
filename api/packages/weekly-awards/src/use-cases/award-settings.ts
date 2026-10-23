import type { MemberId } from '../domain/awards.js';
import {
  AwardSettings,
  type AwardSettings as Settings,
  type AwardSettingsChange,
} from '../domain/settings.js';
import type { AwardSettingsStore } from '../ports.js';

/** What the weekly awards are written with, for the admins to read and change. */
export interface AwardSettingsAdmin {
  current(): Promise<Settings>;
  /**
   * Applies `change` to the current settings and saves them, logged as `by`'s change; nothing is
   * saved or logged when it changes nothing. Returns the settings now.
   */
  change(change: AwardSettingsChange, by: MemberId): Promise<Settings>;
}

export function createAwardSettings(deps: {
  readonly store: AwardSettingsStore;
}): AwardSettingsAdmin {
  return {
    current: () => deps.store.current(),
    change: async ({ moves, ...change }, by) => {
      const current = await deps.store.current();
      const settings = AwardSettings.parse({
        ...current,
        ...change,
        moves: { ...current.moves, ...moves },
      });
      await deps.store.save(settings, by);
      return settings;
    },
  };
}
