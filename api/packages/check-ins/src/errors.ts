import { AppError } from '@wildcard/errors';

/**
 * Thrown when a check-in id is already saved with different contents, or by another member.
 * The app made a new check-in with an old id: give it a new id.
 */
export class CheckInIdConflictError extends AppError {
  override readonly name = 'CheckInIdConflictError';
  readonly reason = 'CHECK_IN_ID_CONFLICT';
  readonly status = 'ALREADY_EXISTS';

  constructor(readonly checkInId: string) {
    super(`Check-in ${checkInId} is already saved with different contents.`);
  }
}

/** Thrown for a second 今日免责声明 on the same day: a member posts at most one a day. */
export class DisclaimerAlreadyPostedError extends AppError {
  override readonly name = 'DisclaimerAlreadyPostedError';
  readonly reason = 'DISCLAIMER_ALREADY_POSTED';
  readonly status = 'ALREADY_EXISTS';

  constructor(readonly day: string) {
    super(`A disclaimer is already posted for ${day}.`);
  }
}

/** Thrown for a check-in made more than 48 hours ago: it waited offline too long to sync. */
export class CheckInTooOldError extends AppError {
  override readonly name = 'CheckInTooOldError';
  readonly reason = 'CHECK_IN_TOO_OLD';
  readonly status = 'INVALID_ARGUMENT';

  constructor() {
    super('A check-in must be saved within 48 hours of being made.');
  }
}

/** Thrown for a check-in made more than 5 minutes ahead of the server: the phone's clock is off. */
export class CheckInInTheFutureError extends AppError {
  override readonly name = 'CheckInInTheFutureError';
  readonly reason = 'CHECK_IN_IN_THE_FUTURE';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('The check-in’s time is ahead of the server’s clock. Check the phone’s clock.');
  }
}

/** Thrown when a check-in's day is more than a day away from when it was made. */
export class CheckInDayMismatchError extends AppError {
  override readonly name = 'CheckInDayMismatchError';
  readonly reason = 'CHECK_IN_DAY_MISMATCH';
  readonly status = 'INVALID_ARGUMENT';

  constructor(readonly day: string) {
    super(`A check-in made at this time can’t count for ${day}.`);
  }
}

/**
 * Thrown when the caller isn't in a squad they name. The same answer whether or not the squad
 * exists, so it reveals nothing about other squads.
 */
export class SquadNotJoinedError extends AppError {
  override readonly name = 'SquadNotJoinedError';
  readonly reason = 'SQUAD_NOT_JOINED';
  readonly status = 'PERMISSION_DENIED';

  constructor(readonly squadId: string) {
    super(`You aren’t in squad ${squadId}.`);
  }
}
