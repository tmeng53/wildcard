import { AppError } from '@wildcard/errors';

/**
 * Thrown when a squad's awards couldn't be written: the model can't be reached, declined, or
 * answered twice with something that failed the checks. Nothing is saved, so the story says the
 * organisers are working late and the next hourly run tries again.
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
