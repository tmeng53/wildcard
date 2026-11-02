// @wildcard/unlocks: what members unlock by training (the character editor's stores and props),
// by rules kept in the database, so a threshold or a sport changes without an app release.

export { createPostgresUnlockStore, type UnlockTables } from './adapters/postgres-unlock-store.js';
export {
  AFTER_MAX,
  ItemId,
  MemberId,
  UNLOCK_KINDS,
  UnlockKind,
  UnlockRuleEdit,
  earned,
  type Trained,
  type Unlock,
  type UnlockRule,
} from './domain/unlocks.js';
export { UnlockSportNotListedError } from './errors.js';
export type { SportListed, TrainedSince, UnlockStore } from './ports.js';
export { createUnlocks, type Unlocks, type UnlocksAdmin } from './use-cases/unlocks.js';
