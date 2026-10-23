import { AppError } from '@wildcard/errors';

/**
 * Thrown when a squad's awards couldn't be written: the model can't be reached, declined, or
 * answered twice naming the wrong members or leaving a title or line blank. Nothing is saved, so
 * the story says the organisers are working late and the next hourly run tries again.
 */
export class AwardsWriterUnavailableError extends AppError {
  override readonly name = 'AwardsWriterUnavailableError';
  readonly reason = 'AWARDS_WRITER_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor(options?: ErrorOptions) {
    super('The awards can’t be written right now. The next run tries again.', options);
  }
}

/**
 * The cause of every failed try on a server with no key for the awards model: kept by name as
 * the week's last error, so the admins' nudge says the key is missing rather than just `Error`.
 */
export class AwardsModelMissingError extends AppError {
  override readonly name = 'AwardsModelMissingError';
  readonly reason = 'AWARDS_MODEL_MISSING';
  readonly status = 'UNAVAILABLE';

  constructor() {
    super('No API key is set for AWARDS_LLM_PROVIDER.');
  }
}

/**
 * Thrown when a week's story is asked for before its awards (Sunday 8pm Eastern): there is
 * nothing to show yet, so the feed shows no tile for it.
 */
export class WeekStoryNotReadyError extends AppError {
  override readonly name = 'WeekStoryNotReadyError';
  readonly reason = 'WEEK_STORY_NOT_READY';
  readonly status = 'NOT_FOUND';

  constructor(readonly weekStart: string) {
    super(`The story of the week from ${weekStart} comes on its Sunday at 8pm Eastern.`);
  }
}
