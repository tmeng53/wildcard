import { AppError } from '@wildcard/errors';

import { MAX_SAVED_PLACES } from './domain/saved-place.js';

/** Thrown when a place without a key (no Apple Maps id) is saved: it can't be found again. */
export class PlaceWithoutKeyError extends AppError {
  override readonly name = 'PlaceWithoutKeyError';
  readonly reason = 'PLACE_WITHOUT_KEY';
  readonly status = 'INVALID_ARGUMENT';

  constructor() {
    super('Only a place with an Apple Maps id can be saved.');
  }
}

/** Thrown when a member who already keeps the most saved places saves another. */
export class TooManySavedPlacesError extends AppError {
  override readonly name = 'TooManySavedPlacesError';
  readonly reason = 'TOO_MANY_SAVED_PLACES';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super(`A member keeps at most ${String(MAX_SAVED_PLACES)} saved places.`);
  }
}
