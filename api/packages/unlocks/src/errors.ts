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

/** Thrown when a rule names a season (scene) the scenes list doesn't have. */
export class UnlockSeasonNotListedError extends AppError {
  override readonly name = 'UnlockSeasonNotListedError';
  readonly reason = 'UNLOCK_SEASON_NOT_LISTED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly season: string) {
    super(`${season} is not on the scenes list.`);
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
