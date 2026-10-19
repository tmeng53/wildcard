import { OpenAPIHono } from '@hono/zod-openapi';
import type { CheckIns, WeeklyPlans } from '@wildcard/check-ins';
import { HTTP_STATUS, isAppError } from '@wildcard/errors';
import type { Members } from '@wildcard/members';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';

import { RequestInvalidError, RouteNotFoundError } from './errors.js';
import type { Log } from './log.js';
import type { Database, PhotoStorage, VerifyToken } from './ports.js';
import { problemResponse } from './problem.js';
import { checkIns } from './routes/check-ins.js';
import { health } from './routes/health.js';
import { me } from './routes/me.js';
import { photoUploads } from './routes/photo-uploads.js';
import { weeklyPlans } from './routes/weekly-plans.js';

export interface AppDependencies {
  readonly db: Database;
  readonly verifyToken: VerifyToken;
  readonly checkIns: CheckIns;
  readonly weeklyPlans: WeeklyPlans;
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
  app.route('/', weeklyPlans(deps));

  app.notFound((c) => problemResponse(new RouteNotFoundError(c.req.method, c.req.path)));
  app.onError((thrown, c) => {
    // Hono's own validator throws a 400 for a body that isn't JSON: answer it like any bad body.
    const error =
      thrown instanceof HTTPException && thrown.status === 400
        ? new RequestInvalidError(thrown.message, { cause: thrown })
        : thrown;
    if (!isAppError(error) || HTTP_STATUS[error.status] >= 500) {
      deps.log.error('request failed', { method: c.req.method, path: c.req.path, error });
    }
    return problemResponse(error);
  });
  return app;
}

export type App = ReturnType<typeof createApp>;
