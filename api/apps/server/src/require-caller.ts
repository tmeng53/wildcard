import { createMiddleware } from 'hono/factory';

import { AppSignInRequiredError, AuthTokenInvalidError, AuthTokenMissingError } from './errors.js';
import { logAlso } from './log.js';
import type { Caller, VerifyToken } from './ports.js';

export interface SignedIn {
  Variables: { caller: Caller };
}

/**
 * Lets the request through only with a valid `Authorization: Bearer <token>` from the app's own
 * sign-in; sets `caller`, and names the member (by id) in the request's log entries. A token issued
 * to an OAuth client is for `/mcp` only.
 */
export function requireCaller(verifyToken: VerifyToken) {
  return createMiddleware<SignedIn>(async (c, next) => {
    const caller = await verifyToken(bearerToken(c.req.header('authorization')));
    if (caller.oauthClient !== undefined) throw new AppSignInRequiredError();
    c.set('caller', caller);
    logAlso({ member: caller.userId });
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
