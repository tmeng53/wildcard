import type { SportId } from '@wildcard/sport-ids';

import type { SportCatalog } from './domain/catalog.js';

/** Where the sports list is kept. */
export interface SportStore {
  /** The whole list, sports the pickers no longer offer included. */
  catalog(): Promise<SportCatalog>;
  /** Whether `id` is a listed sport, offered or not. */
  has(id: SportId): Promise<boolean>;
}
