import { AiUsageSettings, type AiUsageSettingsChange, type MemberId } from '../domain/settings.js';
import type { AiUsageSettingsStore } from '../ports.js';

/** What model calls cost and may spend, for the admins to read and change. */
export interface AiUsageSettingsAdmin {
  current(): Promise<AiUsageSettings>;
  /**
   * Applies `change` to the current settings and saves them, logged as `by`'s change; nothing is
   * saved or logged when it changes nothing. Returns the settings now.
   */
  change(change: AiUsageSettingsChange, by: MemberId): Promise<AiUsageSettings>;
}

export function createAiUsageSettings(deps: {
  readonly store: AiUsageSettingsStore;
}): AiUsageSettingsAdmin {
  return {
    current: () => deps.store.current(),
    change: async (change, by) => {
      const settings = AiUsageSettings.parse({
        ...(await deps.store.current({ forUpdate: true })),
        ...change,
      });
      await deps.store.save(settings, by);
      return settings;
    },
  };
}
