import { AppError } from '@wildcard/errors';

/** Thrown when a file isn't art the app can draw or play, saying why. */
export class ArtRefusedError extends AppError {
  override readonly name = 'ArtRefusedError';
  readonly reason = 'ART_REFUSED';
  readonly status = 'INVALID_ARGUMENT';

  constructor(
    readonly path: string,
    readonly why: string,
  ) {
    super(`${path}: ${why}`);
  }
}

/** Thrown when a file named by its SHA-256 was never uploaded. */
export class ArtFileMissingError extends AppError {
  override readonly name = 'ArtFileMissingError';
  readonly reason = 'ART_FILE_MISSING';
  readonly status = 'NOT_FOUND';

  constructor(readonly sha256: string) {
    super(`No uploaded file has SHA-256 ${sha256}; upload it first with art_upload_url.`);
  }
}

/** Thrown when the art bucket can't be reached. */
export class ArtStorageUnavailableError extends AppError {
  override readonly name = 'ArtStorageUnavailableError';
  readonly reason = 'ART_STORAGE_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor(options?: { readonly cause?: unknown }) {
    super('The art bucket could not be reached.', options);
  }
}
