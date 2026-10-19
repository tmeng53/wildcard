import { OpenAPIHono } from '@hono/zod-openapi';
import type { Admins } from '@wildcard/admins';
import type { CheckIns, WeeklyPlans } from '@wildcard/check-ins';
import { HTTP_STATUS, isAppError } from '@wildcard/errors';
import type { Members } from '@wildcard/members';
import type { Push } from '@wildcard/push';
import type { Squads } from '@wildcard/squads';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';

import { adminMcp } from './admin-mcp/admin-mcp.js';
import type { AdminTool } from './admin-mcp/admin-tool.js';
import { MediaTypeUnsupportedError, RequestInvalidError, RouteNotFoundError } from './errors.js';
import type { Log } from './log.js';
import type { Accounts, Database, PhotoStorage, RevokeAppleSignIn, VerifyToken } from './ports.js';
import { problemResponse } from './problem.js';
import { checkIns } from './routes/check-ins.js';
import { devices } from './routes/devices.js';
import { health } from './routes/health.js';
import { me } from './routes/me.js';
import { photoUploads } from './routes/photo-uploads.js';
import { reactions } from './routes/reactions.js';
import { squads } from './routes/squads.js';
import { squadToday } from './routes/squad-today.js';
import { weeklyPlans } from './routes/weekly-plans.js';

export interface AppDependencies {
  readonly db: Database;
  readonly verifyToken: VerifyToken;
  readonly accounts: Accounts;
  /** Undefined until the Sign in with Apple key is configured. */
  readonly revokeAppleSignIn: RevokeAppleSignIn | undefined;
  readonly checkIns: CheckIns;
  readonly weeklyPlans: WeeklyPlans;
  readonly members: Members;
  readonly squads: Squads;
  readonly photos: PhotoStorage;
  readonly push: Push;
  readonly log: Log;
  /** The admin MCP server at `/mcp`. */
  readonly admin: {
    readonly admins: Admins;
    /** Its tools; `main.ts` lists them. */
    readonly tools: readonly AdminTool[];
    /** Where clients reach this API. */
    readonly publicUrl: URL;
    /** The OAuth 2.1 authorization server that signs admins in. */
    readonly authorizationServer: URL;
  };
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
  app.route('/', reactions(deps));
  app.route('/', devices(deps));
  app.route('/', squads(deps));
  app.route('/', squadToday(deps));
  app.route('/', weeklyPlans(deps));
  // Not part of the app's contract, so not in openapi.json: MCP clients learn its tools from it.
  app.route('/', adminMcp({ ...deps.admin, verifyToken: deps.verifyToken, log: deps.log }));

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
