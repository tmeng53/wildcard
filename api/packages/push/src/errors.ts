import { AppError } from '@wildcard/errors';

/**
 * Thrown when the push service refuses a notification for a reason other than a dead token,
 * e.g. a bad key or a malformed payload. `apnsReason` is Apple's reason, for the log.
 */
export class PushRejectedError extends AppError {
  override readonly name = 'PushRejectedError';
  readonly reason = 'PUSH_REJECTED';
  readonly status = 'INTERNAL';

  constructor(
    readonly httpStatus: number,
    readonly apnsReason: string,
  ) {
    super(`The push service refused a notification (${String(httpStatus)} ${apnsReason}).`);
  }
}

/** Thrown when the push service can't be reached. */
export class PushUnavailableError extends AppError {
  override readonly name = 'PushUnavailableError';
  readonly reason = 'PUSH_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor(options?: ErrorOptions) {
    super('The push service can’t be reached right now.', options);
  }
}
