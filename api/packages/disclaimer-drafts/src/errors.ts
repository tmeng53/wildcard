import { AppError } from '@wildcard/errors';

/**
 * Thrown when a member without a current AI consent asks for drafts. The app shows its dice
 * suggestions. Squads answer with the same reason.
 */
export class AiConsentRequiredError extends AppError {
  override readonly name = 'AiConsentRequiredError';
  readonly reason = 'AI_CONSENT_REQUIRED';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('Agree to the AI terms to get AI drafts. The dice still work.');
  }
}

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

/**
 * Thrown while drafts are off: the settings turn them off, or the server has no key for the
 * settings' model, so they stay off until an admin or a deploy turns them on. The
 * wire answer is the same as `DisclaimerWriterUnavailableError`'s, and the app shows its dice;
 * only the server tells them apart, since this one is expected and not worth an error log.
 */
export class DisclaimerWriterOffError extends AppError {
  override readonly name = 'DisclaimerWriterOffError';
  readonly reason = 'DISCLAIMER_WRITER_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor() {
    super('Drafts can’t be written right now. Try again shortly.');
  }
}
