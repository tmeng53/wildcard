import { decode, verifyWithJwks } from 'hono/jwt';
import { z } from 'zod';

import {
  AuthKeysUnavailableError,
  AuthTokenInvalidError,
  AuthUnavailableError,
} from '../errors.js';
import { UserId, type Accounts, type VerifyToken } from '../ports.js';

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
  // Set only on tokens Supabase Auth's OAuth 2.1 server issued to another app.
  // https://supabase.com/docs/guides/auth/oauth-server/token-security
  client_id: z.string().min(1).max(200).optional(),
});

/** Keys are kept this long, then fetched again so a revoked key stops working. */
const KEYS_MAX_AGE_MS = 10 * 60 * 1000;
/** A token naming a key we don't have fetches the keys again, at most this often. */
const REFETCH_COOLDOWN_MS = 30 * 1000;

/** Supabase Auth's issuer: the authorization server for its tokens and its OAuth 2.1 server. */
export function supabaseAuthIssuer(supabaseUrl: string): URL {
  return new URL(`${supabaseUrl}/auth/v1`);
}

/**
 * The sign-in port on Supabase Auth: verifies its access tokens against the project's published signing keys: the
 * signature, the issuer, the `authenticated` audience and role, and the expiry.
 */
export function createSupabaseTokenVerifier(options: {
  readonly supabaseUrl: string;
  readonly now?: () => number;
}): VerifyToken {
  const issuer = supabaseAuthIssuer(options.supabaseUrl).href;
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
    return { userId: claims.data.sub, oauthClient: claims.data.client_id };
  };
}

// Plain `z.object`: a third party's payload, which carries more fields than we read.
const User = z.object({ id: UserId });
// The sign-in methods linked to a user, each an identity naming its provider.
const Identities = z.object({ identities: z.array(z.object({ provider: z.string() })).nullish() });

/**
 * The accounts port on Supabase Auth's HTTP API. Sessions are checked with the member's own
 * token, which Supabase refuses once its session has signed out; users are deleted with the
 * project's secret key, which only the server holds.
 * https://supabase.com/docs/reference/javascript/auth-getuser
 * https://supabase.com/docs/reference/javascript/auth-admin-deleteuser
 */
export function createSupabaseAccounts(options: {
  readonly supabaseUrl: string;
  readonly secretKey: string;
}): Accounts {
  const base = `${options.supabaseUrl}/auth/v1`;

  const call = async (path: string, init: RequestInit): Promise<Response> => {
    try {
      return await fetch(`${base}${path}`, { ...init, signal: AbortSignal.timeout(5_000) });
    } catch (cause) {
      throw new AuthUnavailableError({ cause });
    }
  };
  const unavailable = async (response: Response) =>
    new AuthUnavailableError({
      cause: new Error(`Auth answered ${String(response.status)}: ${await response.text()}`),
    });

  return {
    async verifySession(token) {
      const response = await call('/user', {
        headers: { apikey: options.secretKey, authorization: `Bearer ${token}` },
      });
      // 401 for a token Auth can't read, 403 for one whose session or user is gone.
      if (response.status === 401 || response.status === 403) {
        throw new AuthTokenInvalidError({
          cause: new Error(`Auth answered ${String(response.status)}: ${await response.text()}`),
        });
      }
      if (!response.ok) throw await unavailable(response);
      return { userId: User.parse(await response.json()).id };
    },
    async deleteUser(userId) {
      const response = await call(`/admin/users/${userId}`, {
        method: 'DELETE',
        headers: { apikey: options.secretKey },
      });
      // 404: deleted already, by an earlier try.
      if (!response.ok && response.status !== 404) throw await unavailable(response);
    },
    async signsInWithApple(userId) {
      const response = await call(`/admin/users/${userId}`, {
        headers: { apikey: options.secretKey },
      });
      if (response.status === 404) return false;
      if (!response.ok) throw await unavailable(response);
      const { identities } = Identities.parse(await response.json());
      return (identities ?? []).some(({ provider }) => provider === 'apple');
    },
  };
}
