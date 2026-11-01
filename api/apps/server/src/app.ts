import { OpenAPIHono } from '@hono/zod-openapi';
import type { Admins } from '@wildcard/admins';
import type { AiConsent } from '@wildcard/ai-consent';
import type { CheckIns, WeekSummaryWords, WeeklyPlans } from '@wildcard/check-ins';
import type { CoachWakes } from '@wildcard/coach';
import { DisclaimerWriterOffError, type DisclaimerDrafts } from '@wildcard/disclaimer-drafts';
import { HTTP_STATUS, isAppError } from '@wildcard/errors';
import type { Members } from '@wildcard/members';
import type { Nudges } from '@wildcard/nudges';
import type { Push } from '@wildcard/push';
import type { Squads } from '@wildcard/squads';
import type { WeeklyAwards } from '@wildcard/weekly-awards';
import { HTTPException } from 'hono/http-exception';
import { routePath } from 'hono/route';
import { z } from 'zod';

import { adminMcp } from './admin-mcp/admin-mcp.js';
import type { AdminTool } from './admin-mcp/admin-tool.js';
import { consentPage } from './admin-mcp/consent-page.js';
import { MediaTypeUnsupportedError, RequestInvalidError, RouteNotFoundError } from './errors.js';
import type { InteractionSource } from './flows/daily-progress-push.js';
import type { Log } from './log.js';
import type {
  Accounts,
  Database,
  IsScheduler,
  OAuthConsent,
  PhotoStorage,
  RevokeAppleSignIn,
  VerifyToken,
} from './ports.js';
import { problemResponse } from './problem.js';
import { requestTrace } from './request-trace.js';
import { awardTotals } from './routes/award-totals.js';
import { aiConsent } from './routes/ai-consent.js';
import { catalog, type CatalogSection } from './routes/catalog.js';
import { checkIns } from './routes/check-ins.js';
import { disclaimerDrafts } from './routes/disclaimer-drafts.js';
import { devices } from './routes/devices.js';
import { health } from './routes/health.js';
import { jobs } from './routes/jobs.js';
import { me } from './routes/me.js';
import { nudges } from './routes/nudges.js';
import { photoUploads } from './routes/photo-uploads.js';
import { pushSettings } from './routes/push-settings.js';
import { comments } from './routes/comments.js';
import { reactions } from './routes/reactions.js';
import { squads, type PublicRoutes } from './routes/squads.js';
import { squadScene } from './routes/squad-scene.js';
import { squadToday } from './routes/squad-today.js';
import { weekStory } from './routes/week-story.js';
import { weekSummary } from './routes/week-summary.js';
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
  /** Squadmates' pokes, which the daily push counts. */
  readonly nudges: Nudges;
  /** Members' consent to the AI copy, which squads and drafts ask for themselves. */
  readonly aiConsent: AiConsent;
  /** What `GET /public/catalog` serves: each section, as `main.ts` lists them. */
  readonly catalog: { readonly sections: readonly CatalogSection[]; readonly clock: () => Date };
  /** Rate limits for the routes anyone can call without signing in. */
  readonly publicRoutes: PublicRoutes;
  readonly photos: PhotoStorage;
  readonly disclaimerDrafts: DisclaimerDrafts;
  readonly push: Push;
  /** The Sunday summary's words now, kept in the database. */
  readonly weekSummaryWords: () => Promise<WeekSummaryWords>;
  /** Each squad's weekly awards, and the clock that says when they are due. */
  readonly weeklyAwards: { readonly awards: WeeklyAwards; readonly clock: () => Date };
  readonly log: Log;
  /** The daily progress push and other work a scheduler starts. */
  readonly jobs: {
    /** Tells the scheduler's token; undefined until one is set up, and then no job runs. */
    readonly isScheduler: IsScheduler | undefined;
    /** Where the daily push finds what teammates did for a member. */
    readonly interactions: readonly InteractionSource[];
    readonly clock: () => Date;
    /** The AI coach's wakes; left out without an OpenAI key, and then the coach never wakes. */
    readonly coach?: CoachWakes;
  };
  /** The admin MCP server at `/mcp`. */
  readonly admin: {
    /** The admin list and log, working on the database or on a transaction of it. */
    readonly admins: (db: Database) => Admins;
    /** Its tools, working on the database or on a transaction of it; `main.ts` lists them. */
    readonly tools: (db: Database) => readonly AdminTool[];
    /** Where clients reach this API. */
    readonly publicUrl: URL;
    /** The OAuth 2.1 authorization server that signs admins in. */
    readonly authorizationServer: URL;
    /** That server's consent step, which the consent page at `/oauth/consent` drives. */
    readonly consent: OAuthConsent;
    /** Admins may sign in there with an email and password (local stacks only). */
    readonly passwordSignIn: boolean;
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
  // First, so everything a request logs carries its trace, and every response its id.
  app.use(requestTrace());

  app.route('/', health(deps));
  app.route('/', catalog({ ...deps.catalog, publicRoutes: deps.publicRoutes }));
  app.route('/', me(deps));
  app.route('/', aiConsent(deps));
  app.route('/', checkIns(deps));
  app.route('/', photoUploads(deps));
  app.route('/', reactions(deps));
  app.route('/', comments(deps));
  app.route('/', devices(deps));
  app.route('/', pushSettings(deps));
  app.route('/', squads(deps));
  app.route('/', squadToday(deps));
  app.route('/', squadScene({ ...deps, clock: deps.weeklyAwards.clock }));
  app.route('/', nudges(deps));
  app.route('/', weekSummary({ ...deps, words: deps.weekSummaryWords }));
  app.route('/', disclaimerDrafts(deps));
  app.route('/', weeklyPlans(deps));
  app.route('/', weekStory({ ...deps, ...deps.weeklyAwards, admins: deps.admin.admins(deps.db) }));
  app.route('/', awardTotals({ ...deps, ...deps.weeklyAwards }));
  // Not part of the app's contract, so not in openapi.json: a scheduler calls it.
  app.route(
    '/',
    jobs({
      isScheduler: deps.jobs.isScheduler,
      dailyProgress: { ...deps, interactions: deps.jobs.interactions, clock: deps.jobs.clock },
      weeklyAwards: { ...deps, ...deps.weeklyAwards, admins: deps.admin.admins(deps.db) },
      ...(deps.jobs.coach === undefined ? {} : { coach: deps.jobs.coach }),
    }),
  );
  // Not part of the app's contract, so not in openapi.json: MCP clients learn its tools from it.
  app.route(
    '/',
    adminMcp({ ...deps.admin, db: deps.db, verifyToken: deps.verifyToken, log: deps.log }),
  );
  // Where the authorization server sends an admin to approve an MCP client: an HTML page.
  app.route(
    '/',
    consentPage({
      consent: deps.admin.consent,
      verifyToken: deps.verifyToken,
      admins: deps.admin.admins(deps.db),
      publicUrl: deps.admin.publicUrl,
      passwordSignIn: deps.admin.passwordSignIn,
      log: deps.log,
    }),
  );

  app.notFound((c) => problemResponse(new RouteNotFoundError(c.req.method, c.req.path)));
  app.onError((thrown, c) => {
    const error = fromHono(thrown);
    // Drafts being off is how the server runs until it has a key, which main.ts logs once.
    const expected = error instanceof DisclaimerWriterOffError;
    const response = problemResponse(error);
    // The route, not the path, so no invite code or id lands in the log or an error report.
    if (!expected && (!isAppError(error) || HTTP_STATUS[error.status] >= 500)) {
      deps.log.error('request failed', { method: c.req.method, route: routePath(c), error });
    } else if (isAppError(error) && response.status < 500) {
      // A refusal is the client's to fix, but it shows which app builds fail and why.
      deps.log.warn('request refused', {
        method: c.req.method,
        route: routePath(c),
        status: response.status,
        reason: error.reason,
      });
    }
    return response;
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
