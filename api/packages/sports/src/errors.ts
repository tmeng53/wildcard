import { AppError } from '@wildcard/errors';

/** Thrown when a sport names a category the list doesn't have: add the category first. */
export class SportCategoryNotFoundError extends AppError {
  override readonly name = 'SportCategoryNotFoundError';
  readonly reason = 'SPORT_CATEGORY_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly category: string) {
    super(`The sports list has no category ${category}.`);
  }
}

/** Thrown when a short list names a sport the list doesn't have, or one it no longer offers. */
export class SportNotOfferedError extends AppError {
  override readonly name = 'SportNotOfferedError';
  readonly reason = 'SPORT_NOT_OFFERED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly sport: string) {
    super(`${sport} is not a sport the pickers offer.`);
  }
}

/** Thrown when retiring a sport a short list still shows: take it off that list first. */
export class SportInPickListError extends AppError {
  override readonly name = 'SportInPickListError';
  readonly reason = 'SPORT_IN_PICK_LIST';
  readonly status = 'FAILED_PRECONDITION';

  constructor(
    readonly sport: string,
    readonly list: string,
  ) {
    super(`${sport} is on the ${list} list; change that list before retiring it.`);
  }
}
