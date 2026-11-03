import { AppError } from '@wildcard/errors';

/** Thrown when a member marks notices seen up to one that isn't theirs (or doesn't exist). */
export class NoticeNotFoundError extends AppError {
  override readonly name = 'NoticeNotFoundError';
  readonly reason = 'NOTICE_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly notice: number) {
    super(`Notice ${String(notice)} isn’t one of yours.`);
  }
}
