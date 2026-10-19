import { createMiddleware } from 'hono/factory';

import { RequestsTooFrequentError } from './errors.js';
import type { RateLimit } from './ports.js';

/**
 * Lets a request through while its client is within `rateLimit`, for routes anyone can call
 * without signing in. `proxyHops` is how many of our own proxies add an address to
 * `X-Forwarded-For` (see `clientAddress`).
 */
export function rateLimited(rateLimit: RateLimit, proxyHops: number) {
  return createMiddleware(async (c, next) => {
    const outcome = rateLimit(clientAddress(c.req.header('x-forwarded-for'), proxyHops));
    if (!outcome.allowed) throw new RequestsTooFrequentError(outcome.retryAfterSeconds);
    await next();
  });
}

/**
 * Who is calling, as far as the server can tell. Each proxy in front of the server adds the
 * address that connected to it at the end of `X-Forwarded-For`, and anything before those the
 * client wrote itself. So the client is the entry `proxyHops` from the end: 1 when one front end
 * adds the client's address, 2 when a load balancer adds the client's and then its own. Without
 * the header (a local run) every request is one client.
 */
export function clientAddress(forwardedFor: string | undefined, proxyHops: number): string {
  const entries = (forwardedFor ?? '').split(',').map((entry) => entry.trim());
  const address = entries.at(-proxyHops);
  return address === undefined || address === '' ? 'unknown' : address;
}
