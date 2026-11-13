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
 * Thrown when a check-in's day is after the one the member posted it on, or more than 7 days
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
 * Thrown for a 请假条 on a day the member already trained on (训练). The app greys that day out:
 * read the member's check-ins again.
 */
export class AlreadyTrainedError extends AppError {
  override readonly name = 'AlreadyTrainedError';
  readonly reason = 'ALREADY_TRAINED';
  readonly status = 'INVALID_ARGUMENT';

  constructor(readonly day: string) {
    super(`The member already trained on ${day}, so it can’t be a rest day.`);
  }
}

/**
 * Thrown for a 训练 or planned day naming a sport id that isn't in the sports list. The app's
 * copy of the list is older or newer than the server's: read `GET /public/catalog` again.
 */
export class SportNotListedError extends AppError {
  override readonly name = 'SportNotListedError';
  readonly reason = 'SPORT_NOT_LISTED';
  readonly status = 'INVALID_ARGUMENT';

  constructor(readonly sport: string) {
    super(`${sport} is not a listed sport.`);
  }
}

/** Thrown when a post is tagged with a squad's place that isn't one of its squads' places. */
export class SquadPlaceNotFoundError extends AppError {
  override readonly name = 'SquadPlaceNotFoundError';
  readonly reason = 'SQUAD_PLACE_NOT_FOUND';
  readonly status = 'INVALID_ARGUMENT';

  constructor(readonly place: string) {
    super(`${place} is not a place of the post's squads.`);
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
 * Thrown for a 训练 from a workout the member already posted: each workout goes out once. The app
 * shows that workout as posted: read the member's check-ins again.
 */
export class WorkoutAlreadyPostedError extends AppError {
  override readonly name = 'WorkoutAlreadyPostedError';
  readonly reason = 'WORKOUT_ALREADY_POSTED';
  readonly status = 'ALREADY_EXISTS';

  constructor() {
    super('The member already posted this workout.');
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

/** Thrown when a member edits or deletes someone else's check-in: each changes only their own. */
export class NotYourCheckInError extends AppError {
  override readonly name = 'NotYourCheckInError';
  readonly reason = 'NOT_YOUR_CHECK_IN';
  readonly status = 'PERMISSION_DENIED';

  constructor() {
    super('You can only change your own check-ins.');
  }
}

/** Thrown for an edit of another kind than the check-in saved: a post keeps its kind. */
export class CheckInKindChangedError extends AppError {
  override readonly name = 'CheckInKindChangedError';
  readonly reason = 'CHECK_IN_KIND_CHANGED';
  readonly status = 'INVALID_ARGUMENT';

  constructor(readonly saved: string) {
    super(`This check-in is a ${saved}; an edit can't change its kind.`);
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

/**
 * Thrown when a comment id is already saved with a different comment, or on another check-in.
 * The app reused an id: give the comment a new one.
 */
export class CommentIdConflictError extends AppError {
  override readonly name = 'CommentIdConflictError';
  readonly reason = 'COMMENT_ID_CONFLICT';
  readonly status = 'ALREADY_EXISTS';

  constructor(readonly commentId: string) {
    super(`Comment ${commentId} is already saved with different contents.`);
  }
}

/** Thrown for a reply to someone who can't see the check-in: a reply names a teammate. */
export class ReplyToCoachNotFoundError extends AppError {
  override readonly name = 'ReplyToCoachNotFoundError';
  readonly reason = 'REPLY_TO_COACH_NOT_FOUND';
  readonly status = 'INVALID_ARGUMENT';

  constructor() {
    super('You can only reply to a coach that said something on this post.');
  }
}

export class ReplyToNotInSquadError extends AppError {
  override readonly name = 'ReplyToNotInSquadError';
  readonly reason = 'REPLY_TO_NOT_IN_SQUAD';
  readonly status = 'INVALID_ARGUMENT';

  constructor() {
    super('You can only reply to someone in the squad.');
  }
}

/** Thrown when a member deletes someone else's comment: each deletes only their own. */
export class NotYourCommentError extends AppError {
  override readonly name = 'NotYourCommentError';
  readonly reason = 'NOT_YOUR_COMMENT';
  readonly status = 'PERMISSION_DENIED';

  constructor() {
    super('You can only delete your own comments.');
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

/** Thrown for a plan or 饮食小目标 more than 4 weeks after the current one. */
export class WeekTooFarAheadError extends AppError {
  override readonly name = 'WeekTooFarAheadError';
  readonly reason = 'WEEK_TOO_FAR_AHEAD';
  readonly status = 'INVALID_ARGUMENT';

  constructor(readonly weekStart: string) {
    super(`The week of ${weekStart} is too far ahead to plan.`);
  }
}

/**
 * Thrown for a change to a day of the current week before today: those days stay as planned.
 */
export class PlanDayStartedError extends AppError {
  override readonly name = 'PlanDayStartedError';
  readonly reason = 'PLAN_DAY_STARTED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly day: string) {
    super(`${day} has already started, so it can’t change in the plan.`);
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
