import { DiceLines, type DiceLine } from '../domain/dice.js';
import type { MemberId } from '../domain/draft-request.js';
import type { DiceLinesStore } from '../ports.js';

/** The 请假条 dice lines, for the catalog to serve and the admins to change. */
export interface DiceLinesAdmin {
  current(): Promise<DiceLines>;
  /**
   * Replaces every line with `lines`, logged as `by`'s change; nothing is saved or logged when
   * they are the lines already. Returns the lines now.
   */
  replace(lines: readonly DiceLine[], by: MemberId): Promise<DiceLines>;
}

export function createDiceLines(deps: { readonly store: DiceLinesStore }): DiceLinesAdmin {
  return {
    current: () => deps.store.current(),
    replace: async (lines, by) => {
      const dice = DiceLines.parse({ version: 1, lines });
      // Held until the transaction ends, so two admins' changes apply one after the other.
      await deps.store.current({ forUpdate: true });
      await deps.store.save(dice, by);
      return dice;
    },
  };
}
