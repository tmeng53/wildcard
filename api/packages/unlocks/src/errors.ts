import { AppError } from '@wildcard/errors';

/** Thrown when a rule names a sport the sports list doesn't have. */
export class UnlockSportNotListedError extends AppError {
  override readonly name = 'UnlockSportNotListedError';
  readonly reason = 'UNLOCK_SPORT_NOT_LISTED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly sport: string) {
    super(`${sport} is not on the sports list.`);
  }
}

/** Thrown when an admin gives a store or prop that has no unlock rule. */
export class UnlockItemMissingError extends AppError {
  override readonly name = 'UnlockItemMissingError';
  readonly reason = 'UNLOCK_ITEM_MISSING';
  readonly status = 'NOT_FOUND';

  constructor(readonly item: string) {
    super(`${item} has no unlock rule.`);
  }
}

/** Thrown when a coach gives a piece the gift pool doesn't offer. */
export class GiftPieceNotOfferedError extends AppError {
  override readonly name = 'GiftPieceNotOfferedError';
  readonly reason = 'GIFT_PIECE_NOT_OFFERED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly piece: string) {
    super(`${piece} is not in the gift pool, or is no longer offered.`);
  }
}

/** Thrown when a member claims a piece they haven't unlocked. */
export class PieceNotUnlockedError extends AppError {
  override readonly name = 'PieceNotUnlockedError';
  readonly reason = 'PIECE_NOT_UNLOCKED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly piece: string) {
    super(`${piece} is not unlocked yet.`);
  }
}
