import type { MemberId } from '../domain/check-in.js';
import { QuickReactions } from '../domain/quick-reactions.js';
import type { QuickReactionsStore } from '../ports.js';

/** The reaction bar's quick emoji, for the catalog to send and admins to change. */
export interface QuickReactionsAdmin {
  current(): Promise<QuickReactions>;
  /** Replaces the list, logged as `by`'s change. Returns it now. */
  replace(emoji: readonly string[], by: MemberId): Promise<QuickReactions>;
}

export function createQuickReactions({
  store,
}: {
  readonly store: QuickReactionsStore;
}): QuickReactionsAdmin {
  return {
    current: () => store.current(),
    replace: async (emoji, by) => {
      const reactions = QuickReactions.parse({ version: 1, emoji });
      await store.save(reactions, by);
      return reactions;
    },
  };
}
