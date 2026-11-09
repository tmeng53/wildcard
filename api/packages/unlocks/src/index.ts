// @wildcard/unlocks: what members unlock by training (the character editor's stores, props and
// clothing pieces), by rules kept in the database, so a threshold or a sport changes without an
// app release; and gifts a squad's coach gives, pieces no store sells.

export { createPostgresGiftStore } from './adapters/postgres-gift-store.js';
export { createPostgresUnlockStore, type UnlockTables } from './adapters/postgres-unlock-store.js';
export {
  AFTER_MAX,
  ItemId,
  MemberId,
  PieceEdit,
  PieceId,
  SLOTS,
  StoreEdit,
  UNLOCK_KINDS,
  UnlockGift,
  UnlockKind,
  UnlockRuleEdit,
  earned,
  idFits,
  shelf,
  toGo,
  type CountedRule,
  type Claim,
  type SwitchOn,
  type Locked,
  type Piece,
  type PieceState,
  type Shelf,
  type Store,
  type Trained,
  type Unlock,
  type UnlockRule,
} from './domain/unlocks.js';
export { TRIGGER_KINDS, type Reward, type Trigger, type TriggerKind } from './domain/rewards.js';
export {
  CoachId,
  GiftPieceEdit,
  GIFT_LINE_LIMIT,
  GivenBy,
  type CoachGift,
  type GiftPiece,
  type GiftRequest,
} from './domain/gifts.js';
export {
  GiftAlreadyOwnedError,
  GiftMemberNotInSquadError,
  GiftNoCoachError,
  GiftNotGivenError,
  GiftPieceNotOfferedError,
  GiftWeeklyLimitError,
  PieceNotUnlockedError,
  UnlockItemMissingError,
  UnlockSportNotListedError,
  UnlockStoreMissingError,
  UnlockSwitchMissingError,
} from './errors.js';
export type { GiftStore, SportListed, TrainedSince, UnlockStore, Unlocked } from './ports.js';
export { createCoachGifts, type CoachGifts, type GiftsAdmin } from './use-cases/gifts.js';
export { createUnlocks, type Unlocks, type UnlocksAdmin } from './use-cases/unlocks.js';
