import { OpenAPIHono } from '@hono/zod-openapi';
import type { CheckIns } from '@wildcard/check-ins';
import { HTTP_STATUS, isAppError } from '@wildcard/errors';
import type { Members } from '@wildcard/members';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';

import { MediaTypeUnsupportedError, RequestInvalidError, RouteNotFoundError } from './errors.js';
import type { Log } from './log.js';
import type { Accounts, Database, PhotoStorage, RevokeAppleSignIn, VerifyToken } from './ports.js';
import { problemResponse } from './problem.js';
import { checkIns } from './routes/check-ins.js';
import { health } from './routes/health.js';
import { me } from './routes/me.js';
import { photoUploads } from './routes/photo-uploads.js';

export interface AppDependencies {
  readonly db: Database;
  readonly verifyToken: VerifyToken;
  readonly accounts: Accounts;
  /** Undefined until the Sign in with Apple key is configured. */
  readonly revokeAppleSignIn: RevokeAppleSignIn | undefined;
  readonly checkIns: CheckIns;
  readonly members: Members;
  readonly photos: PhotoStorage;
  readonly log: Log;
}

/** The HTTP API. The only way into the data; `main.ts` serves it, tests call it directly. */
export function createApp(deps: AppDependencies) {
  const app = new OpenAPIHono({
    // A request that doesn't match its route's schema answers as a problem, like every failure.
    defaultHook: (result) => {
      if (!result.success) throw new RequestInvalidError(z.prettifyError(result.error));
    },
  });
  app.openAPIRegistry.registerComponent('securitySchemes', 'bearer', {
    type: 'http',
    scheme: 'bearer',
    bearerFormat: 'JWT',
    description: 'A Supabase Auth access token.',
  });

  app.route('/', health(deps));
  app.route('/', me(deps));
  app.route('/', checkIns(deps));
  app.route('/', photoUploads(deps));

  app.notFound((c) => problemResponse(new RouteNotFoundError(c.req.method, c.req.path)));
  app.onError((thrown, c) => {
    const error = fromHono(thrown);
    if (!isAppError(error) || HTTP_STATUS[error.status] >= 500) {
      deps.log.error('request failed', { method: c.req.method, path: c.req.path, error });
    }
    return problemResponse(error);
  });
  return app;
}

export type App = ReturnType<typeof createApp>;

/**
 * Our error for one Hono throws itself before a route runs: `@hono/zod-openapi` answers a body
 * in a media type the route doesn't take with 415, and Hono's validator a body that isn't JSON
 * with 400. Anything else is returned as is.
 */
function fromHono(thrown: unknown): unknown {
  if (!(thrown instanceof HTTPException)) return thrown;
  if (thrown.status === 415) return new MediaTypeUnsupportedError({ cause: thrown });
  if (thrown.status === 400) return new RequestInvalidError(thrown.message, { cause: thrown });
  return thrown;
}
