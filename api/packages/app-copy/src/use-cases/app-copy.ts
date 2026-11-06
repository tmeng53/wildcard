import {
  applyChange,
  type AppCopy,
  type AppCopyChange,
  type MemberId,
} from '../domain/app-copy.js';
import type { AppCopyStore } from '../ports.js';

/** The copy put over the app's, for the catalog to serve and the admins to change. */
export interface AppCopyAdmin {
  current(): Promise<AppCopy>;
  /**
   * Applies `change`, logged as `by`'s; nothing is saved or logged when it changes nothing.
   * Returns the copy now.
   */
  change(change: AppCopyChange, by: MemberId): Promise<AppCopy>;
}

export function createAppCopy(deps: { readonly store: AppCopyStore }): AppCopyAdmin {
  return {
    current: () => deps.store.current(),
    change: async (change, by) => {
      // Held until the transaction ends, so two admins' changes apply one after the other.
      const copy = applyChange(await deps.store.current({ forUpdate: true }), change);
      await deps.store.save(copy, by);
      return copy;
    },
  };
}
