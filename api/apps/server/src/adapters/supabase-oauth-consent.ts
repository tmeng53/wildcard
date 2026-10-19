import { z } from 'zod';

import {
  AuthUnavailableError,
  ConsentRequestNotFoundError,
  ConsentSignInRequiredError,
} from '../errors.js';
import type { ConsentSession, OAuthConsent } from '../ports.js';

// Plain `z.object`: a third party's payloads, which carry more fields than we read.
const Session = z.object({ access_token: z.string().min(1) });
const Redirect = z.object({ redirect_url: z.url() });
const Details = z.object({
  redirect_uri: z.string(),
  client: z.object({ name: z.string() }),
  scope: z.string(),
});

/**
 * The consent port on Supabase Auth's OAuth 2.1 server and its sign-in endpoints. Calls carry
 * the project's secret key as `apikey`, as the accounts adapter does, and the member's own token
 * where they act as the member.
 * https://supabase.com/docs/guides/auth/oauth-server/getting-started
 * https://supabase.com/docs/guides/auth/sessions/pkce-flow
 */
export function createSupabaseOAuthConsent(options: {
  readonly supabaseUrl: string;
  readonly secretKey: string;
}): OAuthConsent {
  const base = `${options.supabaseUrl}/auth/v1`;

  const call = async (path: string, init: RequestInit & { readonly token?: string }) => {
    const headers: Record<string, string> = {
      apikey: options.secretKey,
      'content-type': 'application/json',
    };
    if (init.token !== undefined) headers.authorization = `Bearer ${init.token}`;
    try {
      return await fetch(`${base}${path}`, {
        ...init,
        headers,
        signal: AbortSignal.timeout(5_000),
      });
    } catch (cause) {
      throw new AuthUnavailableError({ cause });
    }
  };
  const unavailable = async (response: Response) =>
    new AuthUnavailableError({
      cause: new Error(`Auth answered ${String(response.status)}: ${await response.text()}`),
    });
  // 400 for a wrong password or a used code: Auth's answer for credentials it refuses.
  const session = async (response: Response): Promise<ConsentSession | undefined> => {
    if (response.status === 400) return undefined;
    if (!response.ok) throw await unavailable(response);
    return { accessToken: Session.parse(await response.json()).access_token };
  };
  const authorization = (id: string) => `/oauth/authorizations/${encodeURIComponent(id)}`;
  // What the member's session gets back when it acts on a request.
  const refused = async (response: Response) => {
    // 401 or 403: the session was signed out, so it can't answer any more.
    if (response.status === 401 || response.status === 403) {
      throw new ConsentSignInRequiredError({ cause: await unavailable(response) });
    }
    // 400 for an id that isn't one, 404 for one that expired or was answered.
    if (response.status === 400 || response.status === 404) {
      throw new ConsentRequestNotFoundError({ cause: await unavailable(response) });
    }
    if (!response.ok) throw await unavailable(response);
  };

  return {
    signInWithPassword: async (credentials) =>
      session(
        await call('/token?grant_type=password', {
          method: 'POST',
          body: JSON.stringify(credentials),
        }),
      ),
    appleSignInUrl: ({ redirectTo, codeChallenge }) => {
      const url = new URL(`${base}/authorize`);
      url.searchParams.set('provider', 'apple');
      url.searchParams.set('redirect_to', redirectTo.href);
      url.searchParams.set('code_challenge', codeChallenge);
      url.searchParams.set('code_challenge_method', 's256');
      return url;
    },
    exchangeCode: async ({ code, codeVerifier }) =>
      session(
        await call('/token?grant_type=pkce', {
          method: 'POST',
          body: JSON.stringify({ auth_code: code, code_verifier: codeVerifier }),
        }),
      ),
    request: async (authorizationId, { accessToken }) => {
      const response = await call(authorization(authorizationId), { token: accessToken });
      await refused(response);
      const body: unknown = await response.json();
      const answered = Redirect.safeParse(body);
      if (answered.success) {
        return { kind: 'answered', redirectUrl: new URL(answered.data.redirect_url) };
      }
      const details = Details.parse(body);
      return {
        kind: 'ask',
        clientName: details.client.name,
        redirectUri: details.redirect_uri,
        scope: details.scope,
      };
    },
    answer: async (authorizationId, { session: { accessToken }, approve }) => {
      const response = await call(`${authorization(authorizationId)}/consent`, {
        method: 'POST',
        token: accessToken,
        body: JSON.stringify({ action: approve ? 'approve' : 'deny' }),
      });
      await refused(response);
      return new URL(Redirect.parse(await response.json()).redirect_url);
    },
    signOut: async ({ accessToken }) => {
      const response = await call('/logout?scope=local', { method: 'POST', token: accessToken });
      // 401 or 403: the session is gone already.
      if (!response.ok && response.status !== 401 && response.status !== 403) {
        throw await unavailable(response);
      }
    },
  };
}
