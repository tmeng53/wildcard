import { Coach, type CoachEdit } from '../domain/coach.js';
import type { MemberId } from '../domain/settings.js';
import type { CoachCatalogStore } from '../ports.js';

/** The coaches, for the admins to read, add and change. */
export interface CoachCatalogAdmin {
  /** Every coach, retired ones too, by id. */
  list(): Promise<readonly Coach[]>;
  /**
   * Adds `edit` as a new coach, or replaces the coach with its id whole, logged as `by`'s
   * change; nothing is saved or logged when it changes nothing. Returns the coach now.
   */
  put(edit: CoachEdit, by: MemberId): Promise<Coach>;
}

export function createCoachCatalog(deps: { readonly store: CoachCatalogStore }): CoachCatalogAdmin {
  return {
    list: () => deps.store.list(),
    put: async (edit, by) => {
      const coach = Coach.parse({ version: 2, ...edit });
      await deps.store.save(coach, by);
      return coach;
    },
  };
}
