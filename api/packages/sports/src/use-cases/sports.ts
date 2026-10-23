import { SportId } from '@wildcard/sport-ids';

import type { SportCatalog } from '../domain/catalog.js';
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

export function createSports({ store }: { readonly store: SportStore }): Sports {
  return {
    catalog: () => store.catalog(),
    async isListed(id) {
      const parsed = SportId.safeParse(id);
      return parsed.success && (await store.has(parsed.data));
    },
  };
}
