import { SportId } from '@wildcard/sport-ids';

import { PICK_LISTS, type SportCatalog } from '../domain/catalog.js';
import type { CategoryEdit, PicksEdit, SportEdit } from '../domain/edits.js';
import {
  SportCategoryNotFoundError,
  SportInPickListError,
  SportNotOfferedError,
} from '../errors.js';
import type { SportStore } from '../ports.js';

/** The sports list: what the pickers show, and which sports a check-in or plan may name. */
export interface Sports {
  catalog(): Promise<SportCatalog>;
  /**
   * Whether `id` names a listed sport. Sports the pickers stopped offering still count, so a
   * check-in made before that, waiting on a phone, still saves.
   */
  isListed(id: string): Promise<boolean>;
}

/** Changing the list, for admins. Each change answers with the list as it now is. */
export interface SportsAdmin {
  /** Adds a sport, or replaces every field of one, keeping its id. */
  putSport(edit: SportEdit): Promise<SportCatalog>;
  /** Adds a category, or renames or moves one. */
  putCategory(edit: CategoryEdit): Promise<SportCatalog>;
  /** Replaces a short list; each sport on it must be one the pickers offer. */
  setPicks(edit: PicksEdit): Promise<SportCatalog>;
}

export function createSports({ store }: { readonly store: SportStore }): Sports & SportsAdmin {
  return {
    catalog: () => store.catalog(),
    async isListed(id) {
      const parsed = SportId.safeParse(id);
      return parsed.success && (await store.has(parsed.data));
    },

    async putSport({ position, ...sport }) {
      const catalog = await store.catalog();
      const category = catalog.categories.find(({ id }) => id === sport.category);
      if (category === undefined) throw new SportCategoryNotFoundError(sport.category);
      if (!sport.offered) {
        const list = PICK_LISTS.find((each) => catalog.picks[each].includes(sport.id));
        if (list !== undefined) throw new SportInPickListError(sport.id, list);
      }
      const current = category.sports.findIndex(({ id }) => id === sport.id);
      const others = category.sports.map(({ id }) => id).filter((id) => id !== sport.id);
      await store.saveSport(
        sport,
        placed({ id: sport.id, others, position: position ?? keep(current) }),
      );
      return store.catalog();
    },

    async putCategory({ position, ...category }) {
      const { categories } = await store.catalog();
      const current = categories.findIndex(({ id }) => id === category.id);
      const others = categories.map(({ id }) => id).filter((id) => id !== category.id);
      await store.saveCategory(
        category,
        placed({ id: category.id, others, position: position ?? keep(current) }),
      );
      return store.catalog();
    },

    async setPicks({ list, sports }) {
      const catalog = await store.catalog();
      const offered = new Set(
        catalog.categories.flatMap((category) =>
          category.sports.filter((sport) => sport.offered).map((sport) => sport.id),
        ),
      );
      const missing = sports.find((id) => !offered.has(id));
      if (missing !== undefined) throw new SportNotOfferedError(missing);
      await store.savePicks(list, sports);
      return store.catalog();
    },
  };
}

/** `others` with `id` at `position` (from 1); none, or past the end, puts it last. */
function placed<Id>({
  id,
  others,
  position,
}: {
  readonly id: Id;
  readonly others: readonly Id[];
  readonly position: number | undefined;
}): Id[] {
  const index = Math.min((position ?? Infinity) - 1, others.length);
  return [...others.slice(0, index), id, ...others.slice(index)];
}

/** The place of what is at `index`, from 1; none for something new (-1). */
function keep(index: number): number | undefined {
  return index === -1 ? undefined : index + 1;
}
