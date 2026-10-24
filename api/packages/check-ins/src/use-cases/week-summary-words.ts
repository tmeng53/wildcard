import type { MemberId } from '../domain/check-in.js';
import {
  WeekSummaryWords,
  type WeekSummaryWords as Words,
  type WeekSummaryWordsChange,
} from '../domain/week-summary-words.js';
import type { WeekSummaryWordsStore } from '../ports.js';

/** The Sunday summary's words, for the admins to read and change. */
export interface WeekSummaryWordsAdmin {
  current(): Promise<Words>;
  /**
   * Replaces the awards' and counts' words that `change` names and saves them, logged as
   * `by`'s change; nothing is saved or logged when it changes nothing. Returns the words now.
   */
  change(change: WeekSummaryWordsChange, by: MemberId): Promise<Words>;
}

export function createWeekSummaryWords(deps: {
  readonly store: WeekSummaryWordsStore;
}): WeekSummaryWordsAdmin {
  return {
    current: () => deps.store.current(),
    change: async (change, by) => {
      const current = await deps.store.current({ forUpdate: true });
      const words = WeekSummaryWords.parse({
        version: 1,
        awards: { ...current.awards, ...change.awards },
        stats: { ...current.stats, ...change.stats },
      });
      await deps.store.save(words, by);
      return words;
    },
  };
}
