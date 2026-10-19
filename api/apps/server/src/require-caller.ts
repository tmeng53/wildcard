import { createMiddleware } from 'hono/factory';

import { AuthTokenInvalidError, AuthTokenMissingError } from './errors.js';
import type { Caller, VerifyToken } from './ports.js';

export interface SignedIn {
  Variables: { caller: Caller };
}

/** Lets the request through only with a valid `Authorization: Bearer <token>`; sets `caller`. */
export function requireCaller(verifyToken: VerifyToken) {
  return createMiddleware<SignedIn>(async (c, next) => {
    c.set('caller', await verifyToken(bearerToken(c.req.header('authorization'))));
    await next();
  });
}

/** The token in an `Authorization: Bearer <token>` header; throws when there is none. */
export function bearerToken(header: string | undefined): string {
  if (header === undefined) throw new AuthTokenMissingError();
  const token = /^Bearer +(\S+)$/i.exec(header)?.[1];
  if (token === undefined) throw new AuthTokenInvalidError();
  return token;
}
