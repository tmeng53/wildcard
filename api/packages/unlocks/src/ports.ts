import type { SportId } from '@wildcard/sport-ids';

import type { CoachGift, GiftPiece, GiftPieceEdit } from './domain/gifts.js';
import type { Reward } from './domain/rewards.js';
import type {
  Claim,
  MemberId,
  Piece,
  PieceEdit,
  PieceId,
  Store,
  StoreEdit,
  Trained,
  Unlock,
  UnlockRule,
  UnlockRuleEdit,
} from './domain/unlocks.js';

/** Where the rules and members' unlocks are kept. */
export interface UnlockStore {
  /** Every reward with every trigger it has, by kind and id. */
  rewards(): Promise<Reward[]>;
  /** The `training` triggers, as rules. */
  rules(): Promise<UnlockRule[]>;
  /** Adds a rule counting from now, or changes one, keeping when it counts from. */
  putRule(edit: UnlockRuleEdit): Promise<void>;
  /** Every store, retired ones too, in the street's order. */
  stores(): Promise<Store[]>;
  /** Every piece, retired ones too. */
  pieces(): Promise<Piece[]>;
  /** Adds a store or replaces it whole. */
  putStore(edit: StoreEdit): Promise<void>;
  /** Adds a piece or replaces it whole. */
  putPiece(edit: PieceEdit): Promise<void>;
  /** What `member` unlocked, the earliest first. */
  unlocksOf(member: MemberId): Promise<Unlock[]>;
  /**
   * Keeps `unlocks` for `member`; one already kept stays as it was. Answers with the ones this
   * call kept, so two at once never both count the same unlock as new.
   */
  grant(member: MemberId, unlocks: readonly Unlock[]): Promise<Unlock[]>;
  /** The pieces `member` claimed, the earliest first. */
  claimsOf(member: MemberId): Promise<Claim[]>;
  /**
   * Keeps `member`'s claim of `piece` unless they claimed it already, and answers with the claim
   * as kept. Whether they may claim it is the caller's to check.
   */
  claim(member: MemberId, piece: PieceId): Promise<Claim>;
}

/**
 * Told the unlocks a member just got (by training or as a gift), each once, after they are kept;
 * the server tells the member (通知).
 */
export type Unlocked = (member: MemberId, unlocks: readonly Unlock[]) => Promise<void>;

/** The member's 训练 check-ins made from `since` on, the earliest made first. */
export type TrainedSince = (query: {
  readonly member: MemberId;
  readonly since: Date;
}) => Promise<Trained[]>;

/** Whether `id` is on the sports list. */
export type SportListed = (id: SportId) => Promise<boolean>;

/** Where the gift pool and members' gifts are kept. */
export interface GiftStore {
  /** Every piece in the pool, offered or not, by id. */
  pieces(): Promise<GiftPiece[]>;
  /** Adds a piece to the pool or changes whether it is offered. */
  putPiece(edit: GiftPieceEdit): Promise<void>;
  /** What `member` was given, the earliest first, each with when they opened it. */
  giftsOf(member: MemberId): Promise<CoachGift[]>;
  /** Whether `member` holds `piece` by any way (training, a coach, the team). */
  holds(member: MemberId, piece: PieceId): Promise<boolean>;
  /**
   * Keeps `gift` for `member`, counting for the week that began at `weekStart`; `undefined`
   * when they already have that piece or a gift for that week.
   */
  give(
    member: MemberId,
    gift: Omit<CoachGift, 'givenAt' | 'opened'> & {
      readonly admin?: MemberId;
      readonly weekStart: Date;
    },
  ): Promise<CoachGift | undefined>;
  /**
   * Keeps that `member` opened their gift of `piece` and whether they put it on; false when they
   * weren't given it. Opening it again keeps the first.
   */
  open(opening: {
    readonly member: MemberId;
    readonly piece: PieceId;
    readonly worn: boolean;
  }): Promise<boolean>;
}
