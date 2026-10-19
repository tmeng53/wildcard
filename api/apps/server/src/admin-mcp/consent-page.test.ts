import { createHash, randomBytes } from 'node:crypto';

import { createAdmins, createPostgresAdminStore } from '@wildcard/admins';
import { sql } from 'kysely';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseOAuthConsent } from '../adapters/supabase-oauth-consent.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createLog } from '../log.js';
import { config, signUp } from '../test-kit/local-supabase.js';
import { consentPage } from './consent-page.js';

// The consent page against local Supabase Auth's OAuth 2.1 server: a hand-registered client asks
// for a member's approval, and the member answers on the page, as a browser would.

const db = createDatabase(config.databaseUrl);
const verifyToken = createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl });
const accounts = createSupabaseAccounts({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const consent = createSupabaseOAuthConsent({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const pageWith = (passwordSignIn: boolean) =>
  consentPage({
    consent,
    verifyToken,
    admins: createAdmins({ store: createPostgresAdminStore(db), clock: () => new Date() }),
    publicUrl: new URL('http://localhost:8080'),
    passwordSignIn,
    log: createLog(() => undefined),
  });
const page = pageWith(true);
const callback = 'http://localhost:9999/callback';
let clientId: string;

beforeAll(async () => {
  const response = await fetch(`${config.supabaseUrl}/auth/v1/admin/oauth/clients`, {
    method: 'POST',
    headers: {
      apikey: config.supabaseSecretKey,
      authorization: `Bearer ${config.supabaseSecretKey}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      client_name: 'Claude Code <test>',
      redirect_uris: [callback],
      token_endpoint_auth_method: 'none',
      grant_types: ['authorization_code'],
      response_types: ['code'],
    }),
  });
  clientId = z.object({ client_id: z.uuid() }).parse(await response.json()).client_id;
});
afterAll(async () => {
  await db.destroy();
});

/** A member signed up through local Supabase Auth, on the admin list when asked. */
async function member(options: { admin: boolean }) {
  const signedUp = await signUp();
  if (options.admin) {
    await sql`insert into public.admins (member_id) values (${signedUp.userId})`.execute(db);
  }
  return signedUp;
}

/** The client asks for approval, as an MCP client does: the request's id and its PKCE verifier. */
async function authorizationRequest() {
  const verifier = randomBytes(32).toString('base64url');
  const url = new URL(`${config.supabaseUrl}/auth/v1/oauth/authorize`);
  url.search = new URLSearchParams({
    response_type: 'code',
    client_id: clientId,
    redirect_uri: callback,
    code_challenge: createHash('sha256').update(verifier).digest('base64url'),
    code_challenge_method: 'S256',
  }).toString();
  const redirect = await fetch(url, { redirect: 'manual' });
  const consentUrl = new URL(z.string().parse(redirect.headers.get('location')));
  expect(consentUrl.pathname).toBe('/oauth/consent');
  return { id: z.string().parse(consentUrl.searchParams.get('authorization_id')), verifier };
}

const form = (fields: Record<string, string>) => ({
  method: 'POST',
  headers: { 'content-type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams(fields).toString(),
});
/** The `name=value` of a cookie the response set, as a browser sends it back. */
const cookieFrom = (response: Response) =>
  response.headers.getSetCookie().map((each) => each.split(';')[0] ?? '');

async function signIn(id: string, credentials: { email: string; password: string }) {
  return page.request(
    '/oauth/consent/sign-in',
    form({ authorization_id: id, email: credentials.email, password: credentials.password }),
  );
}

async function answer(id: string, options: { answer: string; cookie: readonly string[] }) {
  const request = form({ authorization_id: id, answer: options.answer });
  return page.request('/oauth/consent/answer', {
    ...request,
    headers: { ...request.headers, cookie: options.cookie.join('; ') },
  });
}

/** Exchanges the code the client got back for its token, as the MCP client does. */
async function tokenFor(redirect: URL, verifier: string) {
  const response = await fetch(`${config.supabaseUrl}/auth/v1/oauth/token`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code: z.string().parse(redirect.searchParams.get('code')),
      redirect_uri: callback,
      client_id: clientId,
      code_verifier: verifier,
    }).toString(),
  });
  return z.object({ access_token: z.string() }).parse(await response.json()).access_token;
}

describe('the consent page', () => {
  it('asks for a fresh sign-in, unframed and uncached', async () => {
    const { id } = await authorizationRequest();
    const response = await page.request(`/oauth/consent?authorization_id=${id}`);

    expect(response.status).toBe(200);
    const body = await response.text();
    expect(body).toContain(`href="/oauth/consent/apple?authorization_id=${id}"`);
    expect(body).toContain('action="/oauth/consent/sign-in"');
    expect({
      csp: response.headers.get('content-security-policy'),
      frame: response.headers.get('x-frame-options'),
      cache: response.headers.get('cache-control'),
    }).toStrictEqual({
      csp: "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",
      frame: 'DENY',
      cache: 'no-store',
    });
  });

  it('lets an admin who just signed in approve, then signs that sign-in out', async () => {
    const admin = await member({ admin: true });
    const { id, verifier } = await authorizationRequest();

    const asked = await signIn(id, admin);
    expect(asked.status).toBe(200);
    // The client's name is escaped, as anything the authorization server sends is.
    expect(await asked.text()).toContain('Let Claude Code &lt;test&gt; manage Wildcard?');
    const cookie = cookieFrom(asked);
    const session = z.string().parse(cookie[0]?.split('~')[1]);

    const approved = await answer(id, { answer: 'approve', cookie });

    expect(approved.status).toBe(303);
    const redirect = new URL(z.string().parse(approved.headers.get('location')));
    expect(redirect.origin + redirect.pathname).toBe(callback);
    const caller = await verifyToken(await tokenFor(redirect, verifier));
    expect(caller).toStrictEqual({ userId: admin.userId, oauthClient: clientId });
    await expect(accounts.verifySession(session)).rejects.toThrow('The sign-in has expired');
    expect(approved.headers.getSetCookie()[0]).toContain('wildcard_consent_session=;');
    // A copy of the cookie kept from before can't answer again: its sign-in is signed out.
    const replayed = await answer(id, { answer: 'approve', cookie });
    expect(replayed.status).toBe(401);
  });

  it('sends a denial back to the client', async () => {
    const admin = await member({ admin: true });
    const { id } = await authorizationRequest();
    const cookie = cookieFrom(await signIn(id, admin));

    const denied = await answer(id, { answer: 'deny', cookie });

    expect(denied.status).toBe(303);
    const redirect = new URL(z.string().parse(denied.headers.get('location')));
    expect(redirect.searchParams.get('error')).toBe('access_denied');
  });

  it('refuses a member who is not an admin', async () => {
    const someone = await member({ admin: false });
    const { id } = await authorizationRequest();

    const refused = await signIn(id, someone);

    expect(refused.status).toBe(403);
    expect(await refused.text()).toContain('This account isn’t an admin');
    expect(refused.headers.getSetCookie()).toStrictEqual([]);
  });

  it('shows the sign-in again for a wrong password', async () => {
    const admin = await member({ admin: true });
    const { id } = await authorizationRequest();

    const refused = await signIn(id, { email: admin.email, password: 'not-the-password' });

    expect(refused.status).toBe(401);
    expect(await refused.text()).toContain('Wrong email or password.');
    expect(refused.headers.getSetCookie()).toStrictEqual([]);
  });

  it('takes an answer only with a sign-in made on the page for that request', async () => {
    const admin = await member({ admin: true });
    const first = await authorizationRequest();
    const second = await authorizationRequest();
    const cookie = cookieFrom(await signIn(first.id, admin));

    const noSignIn = await answer(first.id, { answer: 'approve', cookie: [] });
    const otherRequest = await answer(second.id, { answer: 'approve', cookie });

    // That sign-in is used up, so it can't then answer the request it was made for.
    const afterwards = await answer(first.id, { answer: 'approve', cookie });

    expect([noSignIn.status, otherRequest.status, afterwards.status]).toStrictEqual([
      401, 401, 401,
    ]);
    expect(await noSignIn.text()).toContain('Sign in again to answer this request.');
  });

  it('says a request it doesn’t know has expired', async () => {
    const admin = await member({ admin: true });

    const unknown = await signIn('nosuchrequest', admin);

    expect(unknown.status).toBe(404);
    expect(await unknown.text()).toContain('This sign-in request has expired');
  });

  it('sends the admin to Apple with a PKCE challenge it keeps the verifier of', async () => {
    const { id } = await authorizationRequest();

    const response = await page.request(`/oauth/consent/apple?authorization_id=${id}`);

    expect(response.status).toBe(302);
    const apple = new URL(z.string().parse(response.headers.get('location')));
    const [kept] = cookieFrom(response);
    const verifier = z.string().parse(kept?.split('~')[1]);
    expect({
      at: apple.origin + apple.pathname,
      provider: apple.searchParams.get('provider'),
      back: apple.searchParams.get('redirect_to'),
      challenge: apple.searchParams.get('code_challenge'),
      method: apple.searchParams.get('code_challenge_method'),
      kept: kept?.split('~')[0],
    }).toStrictEqual({
      at: `${config.supabaseUrl}/auth/v1/authorize`,
      provider: 'apple',
      back: 'http://localhost:8080/oauth/consent/callback',
      challenge: createHash('sha256').update(verifier).digest('base64url'),
      method: 's256',
      kept: `wildcard_consent_verifier=${id}`,
    });
    const returned = await page.request('/oauth/consent/callback?code=from-apple');
    expect(returned.status).toBe(401);
  });

  it('offers no password sign-in where it is off', async () => {
    const { id } = await authorizationRequest();
    const off = pageWith(false);

    const shown = await (await off.request(`/oauth/consent?authorization_id=${id}`)).text();
    const posted = await off.request(
      '/oauth/consent/sign-in',
      form({ authorization_id: id, email: 'a@example.com', password: 'x' }),
    );

    expect(shown).not.toContain('/oauth/consent/sign-in');
    expect(posted.status).toBe(404);
  });
});
