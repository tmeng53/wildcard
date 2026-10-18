import { createMiddleware } from 'hono/factory';

import { AuthTokenInvalidError, AuthTokenMissingError } from './errors.js';
import type { Caller, VerifyToken } from './ports.js';

export interface SignedIn {
  Variables: { caller: Caller };
}

/** Lets the request through only with a valid `Authorization: Bearer <token>`; sets `caller`. */
export function requireCaller(verifyToken: VerifyToken) {
  return createMiddleware<SignedIn>(async (c, next) => {
    const header = c.req.header('authorization');
    if (header === undefined) throw new AuthTokenMissingError();
    const token = /^Bearer +(\S+)$/i.exec(header)?.[1];
    if (token === undefined) throw new AuthTokenInvalidError();
    c.set('caller', await verifyToken(token));
    await next();
  });
}
