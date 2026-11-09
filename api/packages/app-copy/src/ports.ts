import type { AppCopy, MemberId } from './domain/app-copy.js';

/** Where the copy put over the app's is kept: one row and its log. */
export interface AppCopyStore {
  /**
   * The copy now. `forUpdate` holds the row until the caller's transaction ends, so two admins
   * changing it at once apply one change after the other.
   */
  current(options?: { readonly forUpdate?: boolean }): Promise<AppCopy>;
  /**
   * Saves `copy` with `by` as who changed it, unless it is the copy already: then nothing is
   * saved or logged. Says whether anything changed.
   */
  save(copy: AppCopy, by: MemberId): Promise<boolean>;
}
