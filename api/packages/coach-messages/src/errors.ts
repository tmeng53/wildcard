import { AppError } from '@wildcard/errors';

/** Thrown when the member never got it (or there is no such message). */
export class CoachMessageNotFoundError extends AppError {
  override readonly name = 'CoachMessageNotFoundError';
  readonly reason = 'COACH_MESSAGE_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly message_: string) {
    super(`You didn’t get ${message_}.`);
  }
}

/** Thrown when an answer doesn't fit its card: a button it hasn't, words it doesn't take. */
export class CoachMessageAnswerInvalidError extends AppError {
  override readonly name = 'CoachMessageAnswerInvalidError';
  readonly reason = 'COACH_MESSAGE_ANSWER_INVALID';
  readonly status = 'INVALID_ARGUMENT';

  constructor(why: string) {
    super(`That doesn’t answer this card: ${why}.`);
  }
}
