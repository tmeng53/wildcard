import type { RateLimit } from '../ports.js';

/**
 * A `RateLimit` kept in this server's memory: at most `limit` requests per key in each fixed
 * window. Each instance counts on its own, so with several instances a key gets up to `limit`
 * from each; that is enough to keep a public lookup from being hammered, not an exact quota.
 * A store every instance shares (Redis, or the load balancer's own limits) replaces it when
 * one is needed.
 */
export function createMemoryRateLimit({
  limit,
  windowSeconds,
  clock,
  maxKeys = 10_000,
}: {
  readonly limit: number;
  readonly windowSeconds: number;
  readonly clock: () => Date;
  /** How many keys it remembers before it forgets the ones whose window has ended. */
  readonly maxKeys?: number;
}): RateLimit {
  const windows = new Map<string, { readonly endsAt: number; count: number }>();
  const windowMs = windowSeconds * 1000;

  function forgetEnded(now: number) {
    for (const [key, window] of windows) if (window.endsAt <= now) windows.delete(key);
    // Every window still running: memory matters more than an exact count, so start over.
    if (windows.size >= maxKeys) windows.clear();
  }

  return (key) => {
    const now = clock().getTime();
    let window = windows.get(key);
    if (window === undefined || window.endsAt <= now) {
      if (window === undefined && windows.size >= maxKeys) forgetEnded(now);
      window = { endsAt: now + windowMs, count: 0 };
      windows.set(key, window);
    }
    if (window.count >= limit) {
      return { allowed: false, retryAfterSeconds: Math.ceil((window.endsAt - now) / 1000) };
    }
    window.count += 1;
    return { allowed: true };
  };
}
