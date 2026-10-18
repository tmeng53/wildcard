import { AppError } from '@wildcard/errors';

/** Thrown when a request that needs a signed-in member carries no bearer token. Sign in. */
export class AuthTokenMissingError extends AppError {
  override readonly name = 'AuthTokenMissingError';
  readonly reason = 'AUTH_TOKEN_MISSING';
  readonly status = 'UNAUTHENTICATED';

  constructor() {
    super('Sign in to do this.');
  }
}

/**
 * Thrown when the bearer token is not a current Supabase access token for a signed-in member:
 * malformed, expired, signed by a key we don't trust, or meant for someone else. Sign in again.
 */
export class AuthTokenInvalidError extends AppError {
  override readonly name = 'AuthTokenInvalidError';
  readonly reason = 'AUTH_TOKEN_INVALID';
  readonly status = 'UNAUTHENTICATED';

  constructor(options?: ErrorOptions) {
    super('The sign-in has expired or is not valid. Sign in again.', options);
  }
}

/** Thrown when Supabase Auth's signing keys can't be fetched, so no token can be checked. Retry. */
export class AuthKeysUnavailableError extends AppError {
  override readonly name = 'AuthKeysUnavailableError';
  readonly reason = 'AUTH_KEYS_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor(options?: ErrorOptions) {
    super('Sign-in can’t be checked right now. Try again shortly.', options);
  }
}

/** Thrown when the database doesn't answer. Retry later. */
export class DatabaseUnavailableError extends AppError {
  override readonly name = 'DatabaseUnavailableError';
  readonly reason = 'DATABASE_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor(options?: ErrorOptions) {
    super('The service is unavailable right now. Try again shortly.', options);
  }
}

/** Thrown for a method and path the API doesn't have. */
export class RouteNotFoundError extends AppError {
  override readonly name = 'RouteNotFoundError';
  readonly reason = 'ROUTE_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(
    readonly method: string,
    readonly path: string,
  ) {
    super(`There is no ${method} ${path}.`);
  }
}
