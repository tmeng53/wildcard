import { describe, expect, it } from 'vitest';

import {
  AuthKeysUnavailableError,
  AuthTokenInvalidError,
  AuthTokenMissingError,
  DatabaseUnavailableError,
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
        new DatabaseUnavailableError(),
        new RouteNotFoundError('GET', '/nope'),
      ].map(({ name, reason, status }) => [name, reason, status]),
    ).toStrictEqual([
      ['AuthTokenMissingError', 'AUTH_TOKEN_MISSING', 'UNAUTHENTICATED'],
      ['AuthTokenInvalidError', 'AUTH_TOKEN_INVALID', 'UNAUTHENTICATED'],
      ['AuthKeysUnavailableError', 'AUTH_KEYS_UNAVAILABLE', 'UNAVAILABLE'],
      ['DatabaseUnavailableError', 'DATABASE_UNAVAILABLE', 'UNAVAILABLE'],
      ['RouteNotFoundError', 'ROUTE_NOT_FOUND', 'NOT_FOUND'],
    ]);
  });
});
