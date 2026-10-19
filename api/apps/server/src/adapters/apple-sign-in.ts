import { createPrivateKey, sign, type KeyObject } from 'node:crypto';

import { z } from 'zod';

import { AppleAuthorizationCodeInvalidError, AppleSignInUnavailableError } from '../errors.js';
import type { RevokeAppleSignIn } from '../ports.js';

// Sign in with Apple's REST API. Revoking takes two calls: trade the app's fresh authorization
// code for a refresh token, then revoke that token, which removes the app from the member's
// Apple ID. Both authenticate with a client secret: a short-lived ES256 JWT signed with the
// team's Sign in with Apple private key (a .p8 file from the Apple Developer account).
// https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple
// https://developer.apple.com/documentation/sign_in_with_apple/generate_and_validate_tokens
// https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens

const APPLE_URL = 'https://appleid.apple.com';
/** Each client secret is made for one revocation, so it only needs to outlive two calls. */
const CLIENT_SECRET_SECONDS = 5 * 60;

// Plain `z.object`: Apple's payloads, which carry more fields than we read.
const Tokens = z.object({ refresh_token: z.string().min(1) });
const TokenError = z.object({ error: z.string() });

export interface AppleSignInKey {
  /** The Apple Developer team id, 10 characters. */
  readonly teamId: string;
  /** The Sign in with Apple key's id, 10 characters. */
  readonly keyId: string;
  /** The key itself: the .p8 file's PEM text. */
  readonly privateKey: string;
  /** Who the tokens were issued to: the app's bundle id for sign-in inside the app. */
  readonly clientId: string;
}

/** The Apple revocation port on Apple's servers. `appleUrl` is for tests. */
export function createAppleSignInRevoker(
  options: AppleSignInKey & { readonly appleUrl?: string; readonly now?: () => number },
): RevokeAppleSignIn {
  const appleUrl = options.appleUrl ?? APPLE_URL;
  const now = options.now ?? Date.now;
  // Parsed once, so a broken key fails at startup instead of on the first deletion.
  const key = createPrivateKey(options.privateKey);

  const post = async (path: string, form: Record<string, string>): Promise<Response> => {
    try {
      return await fetch(`${appleUrl}${path}`, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams(form),
        signal: AbortSignal.timeout(5_000),
      });
    } catch (cause) {
      throw new AppleSignInUnavailableError({ cause });
    }
  };
  const failure = async (response: Response) =>
    new Error(`Apple answered ${String(response.status)}: ${await response.text()}`);

  return async (authorizationCode) => {
    const client = {
      client_id: options.clientId,
      client_secret: clientSecret({ ...options, key, issuedAt: Math.floor(now() / 1000) }),
    };
    const exchanged = await post('/auth/token', {
      ...client,
      code: authorizationCode,
      grant_type: 'authorization_code',
    });
    if (exchanged.status === 400) {
      const body: unknown = await exchanged.json().catch(() => undefined);
      // Apple's word for a code that is expired, used or someone else's.
      if (TokenError.safeParse(body).data?.error === 'invalid_grant') {
        throw new AppleAuthorizationCodeInvalidError({ cause: new Error('invalid_grant') });
      }
      throw new AppleSignInUnavailableError({ cause: new Error(JSON.stringify(body)) });
    }
    if (!exchanged.ok) throw new AppleSignInUnavailableError({ cause: await failure(exchanged) });
    const { refresh_token: refreshToken } = Tokens.parse(await exchanged.json());

    const revoked = await post('/auth/revoke', {
      ...client,
      token: refreshToken,
      token_type_hint: 'refresh_token',
    });
    if (!revoked.ok) throw new AppleSignInUnavailableError({ cause: await failure(revoked) });
  };
}

/** Apple's client secret: a JWT signed with the team's key, ES256 over P-256. */
function clientSecret(
  options: AppleSignInKey & { readonly key: KeyObject; readonly issuedAt: number },
): string {
  const { key, issuedAt } = options;
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const header = encode({ alg: 'ES256', kid: options.keyId });
  const claims = encode({
    iss: options.teamId,
    iat: issuedAt,
    exp: issuedAt + CLIENT_SECRET_SECONDS,
    aud: APPLE_URL,
    sub: options.clientId,
  });
  const signature = sign('sha256', Buffer.from(`${header}.${claims}`), {
    key,
    // A JWT carries the raw r‖s pair, not the DER encoding Node uses by default.
    dsaEncoding: 'ieee-p1363',
  });
  return `${header}.${claims}.${signature.toString('base64url')}`;
}
