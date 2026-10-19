import { AppError } from '@wildcard/errors';

/**
 * Thrown when a member has asked for drafts as often as a day allows (the first batch and 5
 * 换一批). The app shows its dice suggestions until the allowance comes back.
 */
export class DisclaimerDraftsUsedUpError extends AppError {
  override readonly name = 'DisclaimerDraftsUsedUpError';
  readonly reason = 'DISCLAIMER_DRAFTS_USED_UP';
  readonly status = 'RESOURCE_EXHAUSTED';

  constructor() {
    super('No more drafts today. The dice still work.');
  }
}

/**
 * Thrown when no drafts could be written: the model can't be reached, declined, or answered
 * something that failed the checks. The app shows its dice suggestions; asking again may work.
 */
export class DisclaimerWriterUnavailableError extends AppError {
  override readonly name = 'DisclaimerWriterUnavailableError';
  readonly reason = 'DISCLAIMER_WRITER_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor(options?: ErrorOptions) {
    super('Drafts can’t be written right now. Try again shortly.', options);
  }
}
