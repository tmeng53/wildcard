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
