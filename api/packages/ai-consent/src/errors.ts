import { AppError } from '@wildcard/errors';

/**
 * Thrown when a member agrees to terms that aren't the current ones: the app showed copy for
 * an older version or another provider. It reads the terms again and asks again.
 */
export class AiConsentTermsOutdatedError extends AppError {
  override readonly name = 'AiConsentTermsOutdatedError';
  readonly reason = 'AI_CONSENT_TERMS_OUTDATED';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('These aren’t the current AI consent terms. Show the current ones and ask again.');
  }
}
