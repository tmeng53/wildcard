import { createHash, randomBytes } from 'node:crypto';

import { NotAnAdminError, type Admins } from '@wildcard/admins';
import { HTTP_STATUS, isAppError } from '@wildcard/errors';
import { Hono, type Context } from 'hono';
import { deleteCookie, getCookie, setCookie } from 'hono/cookie';
import { html } from 'hono/html';
import type { HtmlEscapedString } from 'hono/utils/html';
import { z } from 'zod';

import { ConsentSignInRequiredError, RequestInvalidError, RouteNotFoundError } from '../errors.js';
import type { Log } from '../log.js';
import type { ConsentSession, OAuthConsent, VerifyToken } from '../ports.js';

// The consent page of the admin MCP sign-in, at `/oauth/consent`, where the authorization
// server sends an admin to approve an MCP client. The admin signs in on this page for this one
// request, every time: the session lives in a cookie for a few minutes and is signed out once
// they answer. Only members on the admin list get to approve; a token from anyone else is
// refused at `/mcp` anyway. An internal page: plain HTML, no scripts.

export interface ConsentPageDependencies {
  readonly consent: OAuthConsent;
  readonly verifyToken: VerifyToken;
  readonly admins: Admins;
  /** Where browsers reach this API; Apple's sign-in comes back under it. */
  readonly publicUrl: URL;
  /** Lets admins sign in with an email and password: local and test stacks only. */
  readonly passwordSignIn: boolean;
  readonly log: Log;
}

const PATH = '/oauth/consent';
/** How long a sign-in on this page may be used to answer, and the Apple sign-in may take. */
const SIGN_IN_MAX_AGE_SECONDS = 5 * 60;
const SESSION_COOKIE = 'wildcard_consent_session';
const VERIFIER_COOKIE = 'wildcard_consent_verifier';

// Supabase's authorization ids are short lowercase strings; anything else isn't one.
const AuthorizationId = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);
const SignIn = z.object({
  authorization_id: AuthorizationId,
  email: z.string().min(1).max(320),
  password: z.string().min(1).max(1024),
});
const Answer = z.object({
  authorization_id: AuthorizationId,
  answer: z.enum(['approve', 'deny']),
});

export function consentPage(deps: ConsentPageDependencies) {
  const secure = deps.publicUrl.protocol === 'https:';
  const cookie = {
    path: PATH,
    httpOnly: true,
    secure,
    sameSite: 'Strict',
    maxAge: SIGN_IN_MAX_AGE_SECONDS,
  } as const;
  const callbackUrl = new URL(`${PATH}/callback`, deps.publicUrl);

  /** Checks the fresh sign-in, then shows what the client asks, or sends an earlier answer on. */
  const afterSignIn = async (
    c: Context,
    {
      authorizationId,
      session,
    }: { readonly authorizationId: string; readonly session: ConsentSession },
  ) => {
    try {
      const caller = await deps.verifyToken(session.accessToken);
      await deps.admins.requireAdmin(caller.userId);
    } catch (error) {
      await deps.consent.signOut(session);
      if (!(error instanceof NotAnAdminError)) throw error;
      return c.html(notAnAdmin(), 403);
    }
    const request = await deps.consent.request(authorizationId, session);
    if (request.kind === 'answered') {
      await deps.consent.signOut(session);
      return c.redirect(request.redirectUrl.href, 303);
    }
    setCookie(c, SESSION_COOKIE, `${authorizationId}~${session.accessToken}`, cookie);
    return c.html(askPage({ authorizationId, ...request }));
  };

  const app = new Hono();
  app.use(`${PATH}/*`, headers);
  app.use(PATH, headers);

  app.get(PATH, (c) => {
    const authorizationId = AuthorizationId.parse(c.req.query('authorization_id'));
    return c.html(signInPage({ authorizationId, passwordSignIn: deps.passwordSignIn }));
  });

  app.get(`${PATH}/apple`, (c) => {
    const authorizationId = AuthorizationId.parse(c.req.query('authorization_id'));
    const verifier = randomBytes(32).toString('base64url');
    setCookie(c, VERIFIER_COOKIE, `${authorizationId}~${verifier}`, { ...cookie, sameSite: 'Lax' });
    const challenge = createHash('sha256').update(verifier).digest('base64url');
    return c.redirect(
      deps.consent.appleSignInUrl({ redirectTo: callbackUrl, codeChallenge: challenge }).href,
    );
  });

  app.get(`${PATH}/callback`, async (c) => {
    const saved = split(getCookie(c, VERIFIER_COOKIE));
    deleteCookie(c, VERIFIER_COOKIE, cookie);
    const code = c.req.query('code');
    if (saved === undefined || code === undefined) throw new ConsentSignInRequiredError();
    const session = await deps.consent.exchangeCode({ code, codeVerifier: saved.secret });
    if (session === undefined) throw new ConsentSignInRequiredError();
    return afterSignIn(c, { authorizationId: saved.authorizationId, session });
  });

  app.post(`${PATH}/sign-in`, async (c) => {
    if (!deps.passwordSignIn) throw new RouteNotFoundError(c.req.method, c.req.path);
    const form = SignIn.parse(await c.req.parseBody());
    const session = await deps.consent.signInWithPassword(form);
    if (session === undefined) {
      const page = signInPage({
        authorizationId: form.authorization_id,
        passwordSignIn: true,
        problem: 'Wrong email or password.',
      });
      return c.html(page, 401);
    }
    return afterSignIn(c, { authorizationId: form.authorization_id, session });
  });

  app.post(`${PATH}/answer`, async (c) => {
    const form = Answer.parse(await c.req.parseBody());
    const saved = split(getCookie(c, SESSION_COOKIE));
    deleteCookie(c, SESSION_COOKIE, cookie);
    if (saved === undefined) throw new ConsentSignInRequiredError();
    const session = { accessToken: saved.secret };
    if (saved.authorizationId !== form.authorization_id) {
      // One sign-in, one answer: a sign-in sent with another request is used up too.
      await deps.consent.signOut(session);
      throw new ConsentSignInRequiredError();
    }
    try {
      // Checked again: the token may have expired, or the admin been taken off the list.
      const caller = await deps.verifyToken(session.accessToken);
      await deps.admins.requireAdmin(caller.userId);
      const next = await deps.consent.answer(form.authorization_id, {
        session,
        approve: form.answer === 'approve',
      });
      return c.redirect(next.href, 303);
    } finally {
      await deps.consent.signOut(session);
    }
  });

  app.onError((error, c) => {
    const known = isAppError(error) && HTTP_STATUS[error.status] < 500;
    if (error instanceof z.ZodError) {
      return htmlResponse(
        problemPage(new RequestInvalidError(z.prettifyError(error)).message),
        400,
      );
    }
    if (known) return htmlResponse(problemPage(error.message), HTTP_STATUS[error.status]);
    deps.log.error('consent page failed', { method: c.req.method, path: c.req.path, error });
    return htmlResponse(problemPage('Something went wrong on our side. Try again shortly.'), 503);
  });
  return app;
}

async function htmlResponse(body: Promise<HtmlEscapedString> | HtmlEscapedString, status: number) {
  return new Response(String(await body), {
    status,
    headers: { 'content-type': 'text/html; charset=UTF-8' },
  });
}

/** The cookie's `<authorization id>~<secret>`, or undefined when there is none. */
function split(value: string | undefined) {
  const at = value?.indexOf('~') ?? -1;
  if (value === undefined || at < 1) return undefined;
  return { authorizationId: value.slice(0, at), secret: value.slice(at + 1) };
}

/** Not framed (an approve button in someone else's frame could be clicked by trickery), not cached, no scripts. */
async function headers(c: Context, next: () => Promise<void>) {
  await next();
  c.header(
    'content-security-policy',
    "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",
  );
  c.header('x-frame-options', 'DENY');
  c.header('cache-control', 'no-store');
  c.header('referrer-policy', 'no-referrer');
}

function page(title: string, body: HtmlEscapedString | Promise<HtmlEscapedString>) {
  return html`<!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>${title} · Wildcard admin</title>
        <style>
          body {
            font:
              16px/1.5 system-ui,
              sans-serif;
            max-width: 26rem;
            margin: 4rem auto;
            padding: 0 1rem;
            color: #111;
          }
          h1 {
            font-size: 1.25rem;
          }
          label,
          input,
          button,
          .button {
            display: block;
            width: 100%;
            box-sizing: border-box;
          }
          input {
            margin: 0.25rem 0 0.75rem;
            padding: 0.5rem;
            font: inherit;
          }
          button,
          .button {
            margin-top: 0.5rem;
            padding: 0.6rem;
            font: inherit;
            text-align: center;
            border: 1px solid #111;
            border-radius: 0.4rem;
            background: #fff;
            color: #111;
            text-decoration: none;
            cursor: pointer;
          }
          .primary {
            background: #111;
            color: #fff;
          }
          .problem {
            color: #a40000;
          }
          dt {
            color: #555;
            font-size: 0.875rem;
          }
          dd {
            margin: 0 0 0.5rem;
            word-break: break-all;
          }
        </style>
      </head>
      <body>
        ${body}
      </body>
    </html>`;
}

function signInPage(options: {
  readonly authorizationId: string;
  readonly passwordSignIn: boolean;
  readonly problem?: string;
}) {
  const { authorizationId } = options;
  return page(
    'Sign in',
    html`<h1>Sign in to approve an app</h1>
      <p>An app is asking to manage Wildcard as you. Sign in again to answer.</p>
      ${options.problem === undefined ? '' : html`<p class="problem">${options.problem}</p>`}
      <a class="button primary" href="${PATH}/apple?authorization_id=${authorizationId}">
        Continue with Apple
      </a>
      ${
        options.passwordSignIn
          ? html`<form method="post" action="${PATH}/sign-in">
              <input type="hidden" name="authorization_id" value="${authorizationId}" />
              <p>Or, on a local stack:</p>
              <label
                >Email <input name="email" type="email" autocomplete="username" required
              /></label>
              <label>
                Password
                <input name="password" type="password" autocomplete="current-password" required />
              </label>
              <button type="submit">Sign in</button>
            </form>`
          : ''
      }`,
  );
}

function askPage(options: {
  readonly authorizationId: string;
  readonly clientName: string;
  readonly redirectUri: string;
  readonly scope: string;
}) {
  return page(
    'Approve',
    html`<h1>Let ${options.clientName} manage Wildcard?</h1>
      <p>
        It can use the admin tools as you until you sign it out. Every change it makes is logged.
      </p>
      <dl>
        <dt>App</dt>
        <dd>${options.clientName}</dd>
        <dt>Sends the answer to</dt>
        <dd>${options.redirectUri}</dd>
        <dt>Scope</dt>
        <dd>${options.scope}</dd>
      </dl>
      <form method="post" action="${PATH}/answer">
        <input type="hidden" name="authorization_id" value="${options.authorizationId}" />
        <button class="primary" type="submit" name="answer" value="approve">Approve</button>
        <button type="submit" name="answer" value="deny">Deny</button>
      </form>`,
  );
}

function notAnAdmin() {
  return page(
    'Not an admin',
    html`<h1>This account isn’t an admin</h1>
      <p>
        Only members on the admin list can let an app manage Wildcard. You’ve been signed out.
      </p>`,
  );
}

function problemPage(message: string) {
  return page(
    'Can’t continue',
    html`<h1>Can’t continue</h1>
      <p class="problem">${message}</p>`,
  );
}
