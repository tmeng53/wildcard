import { timingSafeEqual } from 'node:crypto';

import { verifyWithJwks } from 'hono/jwt';
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
  email: z.string(),
  email_verified: z.literal(true),
});

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
}): IsScheduler {
  return async (token) => {
    let payload: unknown;
    try {
      payload = await verifyWithJwks(
        token,
        {
          jwks_uri: options.keysUrl ?? GOOGLE_KEYS_URL,
          allowedAlgorithms: ['RS256'],
          verification: { iss: /^(https:\/\/)?accounts\.google\.com$/, aud: options.audience },
        },
        { signal: AbortSignal.timeout(5_000) },
      );
    } catch {
      // A bad signature, issuer, audience or expiry, or Google's keys out of reach: no job runs,
      // and the scheduler tries again on its next run.
      return false;
    }
    const claims = GoogleIdToken.safeParse(payload);
    return claims.success && claims.data.email === options.serviceAccount;
  };
}
