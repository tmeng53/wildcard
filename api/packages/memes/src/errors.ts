import { AppError } from '@wildcard/errors';

/** Thrown when turning off a meme the library doesn't have: check the phrase. */
export class MemeNotFoundError extends AppError {
  override readonly name = 'MemeNotFoundError';
  readonly reason = 'MEME_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly phrase: string) {
    super(`The meme library has no 「${phrase}」.`);
  }
}
