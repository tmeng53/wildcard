import type { Coach } from './domain/coach.js';
import type { CoachSettings, MemberId } from './domain/settings.js';

/** Where the coach settings are kept: one value, and a log of every change to it. */
export interface CoachSettingsStore {
  /**
   * The settings now. `forUpdate` holds the row until the caller's transaction ends, so two
   * admins changing them at once apply one change after the other.
   */
  current(options?: { readonly forUpdate?: boolean }): Promise<CoachSettings>;
  /**
   * Saves `settings` with `by` as who changed them, unless they are the settings already: then
   * nothing is saved or logged. Says whether anything changed.
   */
  save(settings: CoachSettings, by: MemberId): Promise<boolean>;
}

/** Where the coaches are kept, with a log of every change to each. */
export interface CoachCatalogStore {
  /** Every coach, retired ones too, by id. */
  list(): Promise<readonly Coach[]>;
  /**
   * Adds `coach`, or replaces the coach with its id, with `by` as who changed it, unless it is
   * that coach already: then nothing is saved or logged. Says whether anything changed.
   */
  save(coach: Coach, by: MemberId): Promise<boolean>;
}
