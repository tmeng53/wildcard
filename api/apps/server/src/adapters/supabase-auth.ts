import { decode, verifyWithJwks } from 'hono/jwt';
import { z } from 'zod';

import { AuthKeysUnavailableError, AuthTokenInvalidError } from '../errors.js';
import { UserId, type VerifyToken } from '../ports.js';

// Supabase signs access tokens with the project's asymmetric signing key (ES256 by default,
// RS256 if the project chose RSA) and publishes the public keys as a JWKS. Symmetric HS256
// tokens, such as the legacy anon and service keys, are never a member's sign-in.
// https://supabase.com/docs/guides/auth/signing-keys
const ALGORITHMS = ['ES256', 'RS256'] as const;

// Plain `z.object`: a third party's payloads, which carry more fields than we read.
const KeySet = z.object({
  keys: z
    .array(
      z.object({
        kid: z.string().max(200),
        kty: z.string().max(10),
        alg: z.string().max(10).optional(),
        crv: z.string().max(10).optional(),
        x: z.string().max(200).optional(),
        y: z.string().max(200).optional(),
        n: z.string().max(2000).optional(),
        e: z.string().max(20).optional(),
      }),
    )
    .max(20),
});
type Key = z.infer<typeof KeySet>['keys'][number];

// Signed in, and not the anon key's role.
const Claims = z.object({
  sub: UserId,
  role: z.literal('authenticated'),
  exp: z.int(),
});

/** Keys are kept this long, then fetched again so a revoked key stops working. */
const KEYS_MAX_AGE_MS = 10 * 60 * 1000;
/** A token naming a key we don't have fetches the keys again, at most this often. */
const REFETCH_COOLDOWN_MS = 30 * 1000;

/**
 * The sign-in port on Supabase Auth: verifies its access tokens against the project's published signing keys: the
 * signature, the issuer, the `authenticated` audience and role, and the expiry.
 */
export function createSupabaseTokenVerifier(options: {
  readonly supabaseUrl: string;
  readonly now?: () => number;
}): VerifyToken {
  const issuer = `${options.supabaseUrl}/auth/v1`;
  const keysUrl = `${issuer}/.well-known/jwks.json`;
  const now = options.now ?? Date.now;

  let keys: readonly Key[] = [];
  let fetchedAt = Number.NEGATIVE_INFINITY;
  let inFlight: Promise<void> | undefined;

  const refresh = async (): Promise<void> => {
    inFlight ??= (async () => {
      try {
        const response = await fetch(keysUrl, { signal: AbortSignal.timeout(5_000) });
        if (!response.ok) throw new Error(`JWKS answered ${String(response.status)}`);
        keys = KeySet.parse(await response.json()).keys;
        fetchedAt = now();
      } catch (cause) {
        throw new AuthKeysUnavailableError({ cause });
      } finally {
        inFlight = undefined;
      }
    })();
    await inFlight;
  };

  const keysFor = async (kid: string): Promise<readonly Key[]> => {
    const age = now() - fetchedAt;
    const known = keys.some((key) => key.kid === kid);
    if (age > KEYS_MAX_AGE_MS || (!known && age > REFETCH_COOLDOWN_MS)) await refresh();
    return keys;
  };

  return async (token) => {
    let kid: unknown;
    try {
      kid = decode(token).header.kid;
    } catch (cause) {
      throw new AuthTokenInvalidError({ cause });
    }
    if (typeof kid !== 'string') throw new AuthTokenInvalidError();

    const trusted = await keysFor(kid);
    let payload: unknown;
    try {
      payload = await verifyWithJwks(token, {
        keys: [...trusted],
        allowedAlgorithms: ALGORITHMS,
        verification: { iss: issuer, aud: 'authenticated' },
      });
    } catch (cause) {
      throw new AuthTokenInvalidError({ cause });
    }
    const claims = Claims.safeParse(payload);
    if (!claims.success) throw new AuthTokenInvalidError({ cause: claims.error });
    return { userId: claims.data.sub };
  };
}
