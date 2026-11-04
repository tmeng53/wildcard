// @wildcard/unlocks: what members unlock by training (the character editor's stores, props and
// clothing pieces), by rules kept in the database, so a threshold or a sport changes without an
// app release.

export { createPostgresUnlockStore, type UnlockTables } from './adapters/postgres-unlock-store.js';
export {
  AFTER_MAX,
  ItemId,
  MemberId,
  PieceId,
  UNLOCK_KINDS,
  UnlockGift,
  UnlockKind,
  UnlockRuleEdit,
  earned,
  idFits,
  toGo,
  type InSeason,
  type Locked,
  type Trained,
  type Unlock,
  type UnlockRule,
} from './domain/unlocks.js';
export {
  UnlockItemMissingError,
  UnlockSeasonNotListedError,
  UnlockSportNotListedError,
} from './errors.js';
export type { Seasons, SportListed, TrainedSince, UnlockStore, Unlocked } from './ports.js';
export { createUnlocks, type Unlocks, type UnlocksAdmin } from './use-cases/unlocks.js';
