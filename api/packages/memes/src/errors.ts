import { AppError } from '@wildcard/errors';

/** Thrown when turning off or back on a meme the library doesn't have: check the phrase. */
export class MemeNotFoundError extends AppError {
  override readonly name = 'MemeNotFoundError';
  readonly reason = 'MEME_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly phrase: string) {
    super(`The meme library has no 「${phrase}」.`);
  }
}

/** Thrown for an expiry at or before the meme's approval: it would never be used. */
export class MemeExpiryBeforeApprovalError extends AppError {
  override readonly name = 'MemeExpiryBeforeApprovalError';
  readonly reason = 'MEME_EXPIRY_BEFORE_APPROVAL';
  readonly status = 'INVALID_ARGUMENT';

  constructor(readonly phrase: string) {
    super(`「${phrase}」 must expire after it was approved.`);
  }
}
