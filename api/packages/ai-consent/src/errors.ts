import { AppError } from '@wildcard/errors';

/**
 * Thrown when a member agrees to a version of the copy that isn't the current one: the app
 * showed older words. It reads the current version and asks again.
 */
export class AiConsentCopyOutdatedError extends AppError {
  override readonly name = 'AiConsentCopyOutdatedError';
  readonly reason = 'AI_CONSENT_COPY_OUTDATED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly copyVersion: number) {
    super(
      `Version ${String(copyVersion)} isn’t the current AI consent copy. Show it and ask again.`,
    );
  }
}
