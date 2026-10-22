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

/** Thrown for a second 今日请假条 on the same day: a member posts at most one a day. */
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

/**
 * Thrown when a check-in's day is one the member hadn't reached when they made it, or is too far
 * before it.
 */
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

/** Thrown for a photo in another member's folder: a member only uses photos they uploaded. */
export class PhotoNotYoursError extends AppError {
  override readonly name = 'PhotoNotYoursError';
  readonly reason = 'PHOTO_NOT_YOURS';
  readonly status = 'PERMISSION_DENIED';

  constructor(readonly path: string) {
    super(`Photo ${path} isn’t one of yours.`);
  }
}

/** Thrown for a photo that hasn't been uploaded: finish the upload, then save again. */
export class PhotoNotUploadedError extends AppError {
  override readonly name = 'PhotoNotUploadedError';
  readonly reason = 'PHOTO_NOT_UPLOADED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly path: string) {
    super(`Photo ${path} hasn’t been uploaded yet.`);
  }
}

/** Thrown for a photo another check-in already uses: each photo belongs to one check-in. */
export class PhotoInUseError extends AppError {
  override readonly name = 'PhotoInUseError';
  readonly reason = 'PHOTO_IN_USE';
  readonly status = 'ALREADY_EXISTS';

  constructor() {
    super('A photo in this check-in is already used by another check-in.');
  }
}

/**
 * Thrown for a check-in the caller can't see: it doesn't exist, or it went to no squad they share
 * with its author. The same answer either way, so it reveals nothing.
 */
export class CheckInNotFoundError extends AppError {
  override readonly name = 'CheckInNotFoundError';
  readonly reason = 'CHECK_IN_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly checkInId: string) {
    super(`There is no check-in ${checkInId} you can see.`);
  }
}

/** Thrown when a member reacts to their own check-in: reactions are for teammates. */
export class OwnCheckInReactionError extends AppError {
  override readonly name = 'OwnCheckInReactionError';
  readonly reason = 'OWN_CHECK_IN_REACTION';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('You can’t react to your own check-in.');
  }
}

/** Thrown when a member replies to their own 请假条: replies are for teammates. */
export class OwnDisclaimerReplyError extends AppError {
  override readonly name = 'OwnDisclaimerReplyError';
  readonly reason = 'OWN_DISCLAIMER_REPLY';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('You can’t reply to your own 请假条.');
  }
}

/** Thrown for a reply to a check-in that isn't a 今日请假条: only a 请假条 takes replies. */
export class NotADisclaimerError extends AppError {
  override readonly name = 'NotADisclaimerError';
  readonly reason = 'NOT_A_DISCLAIMER';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly checkInId: string) {
    super(`Check-in ${checkInId} isn’t a 请假条, so it takes no replies.`);
  }
}

/** Thrown for a change to a past week's plan: past weeks are kept as they were. */
export class WeekOverError extends AppError {
  override readonly name = 'WeekOverError';
  readonly reason = 'WEEK_OVER';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly weekStart: string) {
    super(`The week of ${weekStart} is over, so its plan can’t change.`);
  }
}

/** Thrown for a week that hasn't started yet on the member's clock, so it has nothing to sum up. */
export class WeekNotStartedError extends AppError {
  override readonly name = 'WeekNotStartedError';
  readonly reason = 'WEEK_NOT_STARTED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly weekStart: string) {
    super(`The week of ${weekStart} hasn’t started yet.`);
  }
}

/** Thrown for a plan more than 4 weeks after the current one. */
export class WeekTooFarAheadError extends AppError {
  override readonly name = 'WeekTooFarAheadError';
  readonly reason = 'WEEK_TOO_FAR_AHEAD';
  readonly status = 'INVALID_ARGUMENT';

  constructor(readonly weekStart: string) {
    super(`The week of ${weekStart} is too far ahead to plan.`);
  }
}

/**
 * Thrown for a change to a day of the current week that has already started: earlier days stay
 * as planned, and today stays a training or a rest day.
 */
export class PlanDayStartedError extends AppError {
  override readonly name = 'PlanDayStartedError';
  readonly reason = 'PLAN_DAY_STARTED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly day: string) {
    super(`${day} has already started, so it can’t change in the plan.`);
  }
}

/** Thrown when a change to the current week's plan adds or removes a rest day. Swap days instead. */
export class RestDaysFixedError extends AppError {
  override readonly name = 'RestDaysFixedError';
  readonly reason = 'REST_DAYS_FIXED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly restDays: number) {
    super(`This week keeps ${String(restDays)} rest days. Swap days instead.`);
  }
}

/** Thrown when the member hasn't saved a profile, so their time zone, and so today, is unknown. */
export class TimeZoneNotSetError extends AppError {
  override readonly name = 'TimeZoneNotSetError';
  readonly reason = 'TIME_ZONE_NOT_SET';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('Save your profile with your time zone first.');
  }
}
