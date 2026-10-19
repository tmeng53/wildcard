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

/** Thrown when the sign-in provider itself doesn't answer, so a session can't be checked or a user deleted. Retry. */
export class AuthUnavailableError extends AppError {
  override readonly name = 'AuthUnavailableError';
  readonly reason = 'AUTH_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor(options?: ErrorOptions) {
    super('Sign-in can’t be checked right now. Try again shortly.', options);
  }
}

/**
 * Thrown when Apple refuses a Sign in with Apple authorization code: expired (codes last 5
 * minutes), used already, or for another app. Ask Apple for a new one and send it again.
 */
export class AppleAuthorizationCodeInvalidError extends AppError {
  override readonly name = 'AppleAuthorizationCodeInvalidError';
  readonly reason = 'APPLE_AUTHORIZATION_CODE_INVALID';
  readonly status = 'INVALID_ARGUMENT';

  constructor(options?: ErrorOptions) {
    super('Apple didn’t accept that authorization code. Sign in with Apple again.', options);
  }
}

/**
 * Thrown when a member who signs in with Apple deletes their account without a fresh Sign in
 * with Apple authorization code, so Apple's grant can't be revoked. Ask Apple for one and send
 * it.
 */
export class AppleAuthorizationCodeRequiredError extends AppError {
  override readonly name = 'AppleAuthorizationCodeRequiredError';
  readonly reason = 'APPLE_AUTHORIZATION_CODE_REQUIRED';
  readonly status = 'INVALID_ARGUMENT';

  constructor() {
    super('This account signs in with Apple. Sign in with Apple again to delete it.');
  }
}

/** Thrown when Apple's Sign in with Apple servers don't answer. Retry. */
export class AppleSignInUnavailableError extends AppError {
  override readonly name = 'AppleSignInUnavailableError';
  readonly reason = 'APPLE_SIGN_IN_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor(options?: ErrorOptions) {
    super('Apple can’t be reached right now. Try again shortly.', options);
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

/**
 * Thrown when a request's body isn't sent as JSON (`text/plain`, or no `Content-Type` at all) to a
 * route that takes JSON. Send it as `application/json`. Answered with HTTP 415, as RFC 9110 asks.
 */
export class MediaTypeUnsupportedError extends AppError {
  override readonly name = 'MediaTypeUnsupportedError';
  readonly reason = 'MEDIA_TYPE_UNSUPPORTED';
  readonly status = 'INVALID_ARGUMENT';

  constructor(options?: ErrorOptions) {
    super('Send the body as application/json.', options);
  }
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
 * Thrown when a token issued to an OAuth client (an MCP client signing an admin in) calls the
 * app's routes: those take only the app's own sign-in, so a third-party client a member
 * approved can't act as them.
 */
export class AppSignInRequiredError extends AppError {
  override readonly name = 'AppSignInRequiredError';
  readonly reason = 'APP_SIGN_IN_REQUIRED';
  readonly status = 'UNAUTHENTICATED';

  constructor() {
    super('Sign in from the app to do this.');
  }
}

/**
 * Thrown when the admin tools get a token from our own app's sign-in. Admin tools take only a
 * token issued to an MCP client through the OAuth sign-in, which keeps the two kinds of token
 * apart. Sign in from the MCP client.
 */
export class AdminSignInRequiredError extends AppError {
  override readonly name = 'AdminSignInRequiredError';
  readonly reason = 'ADMIN_SIGN_IN_REQUIRED';
  readonly status = 'UNAUTHENTICATED';

  constructor() {
    super('Sign in from your MCP client to use the admin tools.');
  }
}

/**
 * Thrown when a caller asks a route anyone can call too often. Wait `retryAfterSeconds`, which
 * the response also gives as `Retry-After`.
 */
export class RequestsTooFrequentError extends AppError {
  override readonly name = 'RequestsTooFrequentError';
  readonly reason = 'REQUESTS_TOO_FREQUENT';
  readonly status = 'RESOURCE_EXHAUSTED';

  constructor(readonly retryAfterSeconds: number) {
    super('Too many requests. Try again shortly.');
  }
}
