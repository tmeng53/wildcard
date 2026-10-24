import type { SportId } from '@wildcard/sport-ids';

import type { LocalizedNames, PickList, SportCatalog } from './domain/catalog.js';

/** A sport as the list keeps it, apart from its place. */
export interface SportRecord {
  readonly id: SportId;
  readonly category: string;
  readonly names: LocalizedNames;
  readonly shortNames?: LocalizedNames;
  readonly icon: string;
  readonly offered: boolean;
}

/** Where the sports list is kept. */
export interface SportStore {
  /** The whole list, sports the pickers no longer offer included. */
  catalog(): Promise<SportCatalog>;
  /** Whether `id` is a listed sport, offered or not. */
  has(id: SportId): Promise<boolean>;
  /**
   * Adds or replaces `sport`, with `order` the ids of its category's sports in their new
   * order, `sport` among them. A sport that moved category leaves no gap behind.
   */
  saveSport(sport: SportRecord, order: readonly SportId[]): Promise<void>;
  /** Adds or replaces a category, with `order` every category's id in their new order. */
  saveCategory(
    category: { readonly id: string; readonly names: LocalizedNames },
    order: readonly string[],
  ): Promise<void>;
  /** Replaces a short list with `sports`, in order. */
  savePicks(list: PickList, sports: readonly SportId[]): Promise<void>;
}
