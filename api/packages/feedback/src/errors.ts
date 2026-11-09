import { AppError } from '@wildcard/errors';

/** Thrown when a member sent as many messages as a day allows: they can email us instead. */
export class FeedbackLimitError extends AppError {
  override readonly name = 'FeedbackLimitError';
  readonly reason = 'FEEDBACK_LIMIT';
  readonly status = 'RESOURCE_EXHAUSTED';

  constructor(readonly limit: number) {
    super(`You can send ${String(limit)} messages a day.`);
  }
}

/** Thrown when another member's message already has this id. */
export class FeedbackIdTakenError extends AppError {
  override readonly name = 'FeedbackIdTakenError';
  readonly reason = 'FEEDBACK_ID_TAKEN';
  readonly status = 'ALREADY_EXISTS';

  constructor(readonly id: string) {
    super(`Feedback ${id} already exists.`);
  }
}

/** Thrown when a message has no words, too many, or too many screenshots. */
export class FeedbackInvalidError extends AppError {
  override readonly name = 'FeedbackInvalidError';
  readonly reason = 'FEEDBACK_INVALID';
  readonly status = 'INVALID_ARGUMENT';
}

/** Thrown when an admin adopts a message that doesn't exist (or went with its account). */
export class FeedbackMissingError extends AppError {
  override readonly name = 'FeedbackMissingError';
  readonly reason = 'FEEDBACK_MISSING';
  readonly status = 'NOT_FOUND';

  constructor(readonly id: string) {
    super(`There is no feedback ${id}.`);
  }
}
