import { timingSafeEqual } from 'node:crypto';

import { decode, verifyWithJwks } from 'hono/jwt';
import { z } from 'zod';

import type { IsScheduler } from '../ports.js';

/**
 * The scheduler on a local stack and in tests: it sends `JOBS_TOKEN`, a long random secret.
 * Compared in constant time, so a wrong token can't be guessed a byte at a time.
 */
export function jobsTokenScheduler(jobsToken: string): IsScheduler {
  const expected = Buffer.from(jobsToken);
  return (token) => {
    const given = Buffer.from(token);
    return Promise.resolve(given.length === expected.length && timingSafeEqual(given, expected));
  };
}

/** Where Google publishes the keys it signs OIDC ID tokens with. */
export const GOOGLE_KEYS_URL = 'https://www.googleapis.com/oauth2/v3/certs';

// Plain `z.object`: a third party's payload, which carries more fields than we read.
const GoogleIdToken = z.object({
  exp: z.number(),
  email: z.string(),
  email_verified: z.literal(true),
});
const Jwks = z.object({
  keys: z.array(
    z.object({
      kid: z.string(),
      kty: z.string(),
      alg: z.string().optional(),
      use: z.string().optional(),
      n: z.string().optional(),
      e: z.string().optional(),
    }),
  ),
});
type Jwk = z.infer<typeof Jwks>['keys'][number];

/** How long Google's keys are kept when its answer carries no `max-age`. */
const DEFAULT_KEYS_AGE_MS = 60 * 60 * 1000;
/** A token signed with a key we don't have refetches the keys at most this often. */
const UNKNOWN_KEY_REFETCH_MS = 60 * 1000;

/**
 * Google's keys, kept as long as its `Cache-Control` says and fetched again early only for a key
 * id we haven't seen (Google rotates them), at most once a minute. So a stranger's token can't
 * make the API call Google on every request. A fetch that fails keeps nothing.
 */
function googleKeys(url: string, now: () => number) {
  let cached: { keys: Jwk[]; fetchedAt: number; maxAgeMs: number } | undefined;
  let fetching: Promise<Jwk[]> | undefined;
  const fetchKeys = async () => {
    const response = await fetch(url, { signal: AbortSignal.timeout(5_000) });
    if (!response.ok) throw new Error(`Google's keys answered ${String(response.status)}`);
    const maxAge = /max-age=(\d+)/.exec(response.headers.get('cache-control') ?? '')?.[1];
    const keys = Jwks.parse(await response.json()).keys;
    cached = {
      keys,
      fetchedAt: now(),
      maxAgeMs: maxAge === undefined ? DEFAULT_KEYS_AGE_MS : Number(maxAge) * 1000,
    };
    return keys;
  };
  return async (kid: string): Promise<Jwk[]> => {
    if (cached !== undefined) {
      const age = now() - cached.fetchedAt;
      const known = cached.keys.some((key) => key.kid === kid);
      if (age < cached.maxAgeMs && (known || age < UNKNOWN_KEY_REFETCH_MS)) return cached.keys;
    }
    fetching ??= fetchKeys().finally(() => {
      fetching = undefined;
    });
    return fetching;
  };
}

/**
 * The hosted scheduler: Cloud Scheduler sends an OIDC ID token Google signs for its own service
 * account, so no shared secret sits in the job's settings. Taken only when Google signed it
 * (RS256, against Google's published keys), for this API (`audience`), for that one account,
 * and it hasn't expired.
 * https://cloud.google.com/scheduler/docs/http-target-auth
 * https://developers.google.com/identity/openid-connect/openid-connect#validatinganidtoken
 */
export function googleScheduler(options: {
  /** The service account Cloud Scheduler signs as, `…@<project>.iam.gserviceaccount.com`. */
  readonly serviceAccount: string;
  /** The audience the jobs are created with: this API's public URL. */
  readonly audience: string;
  readonly keysUrl?: string;
  readonly now?: () => number;
}): IsScheduler {
  const keysFor = googleKeys(options.keysUrl ?? GOOGLE_KEYS_URL, options.now ?? Date.now);
  return async (token) => {
    let payload: unknown;
    try {
      const { kid } = z.object({ kid: z.string() }).parse(decode(token).header);
      payload = await verifyWithJwks(token, {
        keys: await keysFor(kid),
        allowedAlgorithms: ['RS256'],
        verification: { iss: /^(https:\/\/)?accounts\.google\.com$/, aud: options.audience },
      });
    } catch {
      // A bad signature, issuer, audience or expiry, or Google's keys out of reach: no job runs,
      // and the scheduler tries again on its next run.
      return false;
    }
    const claims = GoogleIdToken.safeParse(payload);
    return claims.success && claims.data.email === options.serviceAccount;
  };
}
