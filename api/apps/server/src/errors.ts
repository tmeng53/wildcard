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

/** Thrown when a request's path, query or body isn't what the route takes. Fix the request. */
export class RequestInvalidError extends AppError {
  override readonly name = 'RequestInvalidError';
  readonly reason = 'REQUEST_INVALID';
  readonly status = 'INVALID_ARGUMENT';
}

/** Thrown when photo storage doesn't answer. Retry later. */
export class PhotoStorageUnavailableError extends AppError {
  override readonly name = 'PhotoStorageUnavailableError';
  readonly reason = 'PHOTO_STORAGE_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor(options?: ErrorOptions) {
    super('Photos are unavailable right now. Try again shortly.', options);
  }
}

/** Thrown when no photo has been uploaded to a path. */
export class PhotoNotFoundError extends AppError {
  override readonly name = 'PhotoNotFoundError';
  readonly reason = 'PHOTO_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly path: string) {
    super('That photo doesn’t exist.');
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

/**
 * Thrown when the admin tools get a token from our own app's sign-in. Admin tools take only a
 * token issued to the MCP client through the OAuth sign-in, so a token from a phone can't reach
 * them. Sign in from the MCP client.
 */
export class AdminSignInRequiredError extends AppError {
  override readonly name = 'AdminSignInRequiredError';
  readonly reason = 'ADMIN_SIGN_IN_REQUIRED';
  readonly status = 'UNAUTHENTICATED';

  constructor() {
    super('Sign in from your MCP client to use the admin tools.');
  }
}
