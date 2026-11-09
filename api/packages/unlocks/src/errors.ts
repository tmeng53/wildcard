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

/** Thrown when an admin hangs a piece in a store that doesn't exist. */
export class UnlockStoreMissingError extends AppError {
  override readonly name = 'UnlockStoreMissingError';
  readonly reason = 'UNLOCK_STORE_MISSING';
  readonly status = 'NOT_FOUND';

  constructor(readonly store: string) {
    super(`There is no store ${store}.`);
  }
}

/** Thrown when an admin has a store or piece follow a switch that doesn't exist. */
export class UnlockSwitchMissingError extends AppError {
  override readonly name = 'UnlockSwitchMissingError';
  readonly reason = 'UNLOCK_SWITCH_MISSING';
  readonly status = 'NOT_FOUND';

  constructor(readonly switchId: string) {
    super(`There is no switch ${switchId} (get_switches lists them).`);
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

/** Thrown when a member is given a piece they already have. */
export class GiftAlreadyOwnedError extends AppError {
  override readonly name = 'GiftAlreadyOwnedError';
  readonly reason = 'GIFT_ALREADY_OWNED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly piece: string) {
    super(`The member already has ${piece}.`);
  }
}

/** Thrown when a member who was given a gift this week is given another (one a week at most). */
export class GiftWeeklyLimitError extends AppError {
  override readonly name = 'GiftWeeklyLimitError';
  readonly reason = 'GIFT_WEEKLY_LIMIT';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly lastGivenAt: Date) {
    super(`The member was given a gift this week already (${lastGivenAt.toISOString()}).`);
  }
}

/** Thrown when a member opens a gift they weren't given. */
export class GiftNotGivenError extends AppError {
  override readonly name = 'GiftNotGivenError';
  readonly reason = 'GIFT_NOT_GIVEN';
  readonly status = 'NOT_FOUND';

  constructor(readonly piece: string) {
    super(`The member wasn't given ${piece}.`);
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

export class GiftNoCoachError extends AppError {
  override readonly name = 'GiftNoCoachError';
  readonly reason = 'GIFT_NO_COACH';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('The squad has no coach to give it from (hire_coach first).');
  }
}

export class GiftMemberNotInSquadError extends AppError {
  override readonly name = 'GiftMemberNotInSquadError';
  readonly reason = 'GIFT_MEMBER_NOT_IN_SQUAD';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('The member is not in that squad now.');
  }
}

/** Thrown when an admin names a badge or voucher that isn't in its catalog. */
export class RewardMissingError extends AppError {
  override readonly name = 'RewardMissingError';
  readonly reason = 'REWARD_MISSING';
  readonly status = 'NOT_FOUND';

  constructor(readonly reward: string) {
    super(`There is no ${reward} (put_badge or put_voucher adds one).`);
  }
}

/** Thrown when an admin gives a reward that has no offered `team` trigger. */
export class RewardNotTeamGivenError extends AppError {
  override readonly name = 'RewardNotTeamGivenError';
  readonly reason = 'REWARD_NOT_TEAM_GIVEN';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly reward: string) {
    super(`${reward} is not one the team gives (put_reward_trigger with way team adds that).`);
  }
}
