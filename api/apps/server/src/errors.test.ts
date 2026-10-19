import { describe, expect, it } from 'vitest';

import {
  AppleAuthorizationCodeInvalidError,
  AppleSignInUnavailableError,
  AuthKeysUnavailableError,
  AuthTokenInvalidError,
  AuthTokenMissingError,
  AuthUnavailableError,
  DatabaseUnavailableError,
  MediaTypeUnsupportedError,
  RequestInvalidError,
  RouteNotFoundError,
} from './errors.js';

// Every error the server throws, so a changed reason or status shows up as a diff.
describe('server errors', () => {
  it('each has its reason and status', () => {
    expect(
      [
        new AuthTokenMissingError(),
        new AuthTokenInvalidError(),
        new AuthKeysUnavailableError(),
        new AuthUnavailableError(),
        new AppleAuthorizationCodeInvalidError(),
        new AppleSignInUnavailableError(),
        new DatabaseUnavailableError(),
        new RequestInvalidError('bad'),
        new MediaTypeUnsupportedError(),
        new RouteNotFoundError('GET', '/nope'),
      ].map(({ name, reason, status }) => [name, reason, status]),
    ).toStrictEqual([
      ['AuthTokenMissingError', 'AUTH_TOKEN_MISSING', 'UNAUTHENTICATED'],
      ['AuthTokenInvalidError', 'AUTH_TOKEN_INVALID', 'UNAUTHENTICATED'],
      ['AuthKeysUnavailableError', 'AUTH_KEYS_UNAVAILABLE', 'UNAVAILABLE'],
      ['AuthUnavailableError', 'AUTH_UNAVAILABLE', 'UNAVAILABLE'],
      [
        'AppleAuthorizationCodeInvalidError',
        'APPLE_AUTHORIZATION_CODE_INVALID',
        'INVALID_ARGUMENT',
      ],
      ['AppleSignInUnavailableError', 'APPLE_SIGN_IN_UNAVAILABLE', 'UNAVAILABLE'],
      ['DatabaseUnavailableError', 'DATABASE_UNAVAILABLE', 'UNAVAILABLE'],
      ['RequestInvalidError', 'REQUEST_INVALID', 'INVALID_ARGUMENT'],
      ['MediaTypeUnsupportedError', 'MEDIA_TYPE_UNSUPPORTED', 'INVALID_ARGUMENT'],
      ['RouteNotFoundError', 'ROUTE_NOT_FOUND', 'NOT_FOUND'],
    ]);
  });
});
