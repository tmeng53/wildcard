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
export {
  BadgeEdit,
  BadgeLines,
  BadgeNames,
  CatalogRewardId,
  EventName,
  GivenKind,
  REWARD_KINDS,
  RewardKind,
  RewardTriggerEdit,
  TRIGGER_KINDS,
  VOUCHER_DAYS_MAX,
  VoucherEdit,
  rewardIdFits,
  type Badge,
  type Given,
  type HeldBadge,
  type Occurrence,
  type Reward,
  type TeamPiece,
  type Trigger,
  type TriggerKind,
  type Voucher,
} from './domain/rewards.js';
export { createPostgresRewardStore } from './adapters/postgres-reward-store.js';
export { createRewards, type Rewards, type RewardsAdmin } from './use-cases/rewards.js';
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
  BadgeNotHeldError,
  GiftAlreadyOwnedError,
  GiftMemberNotInSquadError,
  GiftNoCoachError,
  GiftNotGivenError,
  GiftPieceNotOfferedError,
  GiftWeeklyLimitError,
  PieceNotUnlockedError,
  RewardMissingError,
  RewardNotTeamGivenError,
  UnlockItemMissingError,
  UnlockSportNotListedError,
  UnlockStoreMissingError,
  UnlockSwitchMissingError,
} from './errors.js';
export type {
  GiftStore,
  RewardStore,
  SportListed,
  TrainedSince,
  UnlockStore,
  Unlocked,
} from './ports.js';
export { createCoachGifts, type CoachGifts, type GiftsAdmin } from './use-cases/gifts.js';
export { createUnlocks, type Unlocks, type UnlocksAdmin } from './use-cases/unlocks.js';
