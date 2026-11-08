import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import type { Members } from '@wildcard/members';
import { MemberId, NoticeId, type Notices } from '@wildcard/notices';
import { streamSSE } from 'hono/streaming';

import { bodyVersion } from '../body-version.js';
import type { Log } from '../log.js';
import type { LiveEvents, VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import type { CoachNames } from '../flows/coach-names.js';
import { NoticeEntry, noticeEntries } from './notices.js';

/** How long the app waits before reconnecting after the stream ends, in milliseconds. */
const RETRY_MS = 3_000;

export interface StreamTiming {
  /** How often a quiet stream sends a comment, so proxies and the app know it is alive. */
  readonly heartbeatMs: number;
  /**
   * How long one stream lasts before the server ends it and the app reconnects with a fresh
   * token: under Cloud Run's request timeout (`--timeout` in deploy.yml), and under the access
   * token's hour, so a signed-out session doesn't keep hearing.
   */
  readonly maxAgeMs: number;
}

const TIMING: StreamTiming = { heartbeatMs: 25_000, maxAgeMs: 50 * 60_000 };

export const LiveReady = z
  .strictObject({ version: bodyVersion(1) })
  .openapi('LiveReady', { description: 'The `ready` event’s data.' });

export const LiveNotice = z
  .strictObject({
    version: bodyVersion(1),
    notice: NoticeEntry.meta({ description: 'As `GET /me/notices` lists it.' }),
  })
  .openapi('LiveNotice', { description: 'The `notice` event’s data.' });

export const LiveShelf = z.strictObject({ version: bodyVersion(1) }).openapi('LiveShelf', {
  description:
    'The `shelf` event’s data: what the caller’s 商店街 shows may have changed, so read ' +
    '`GET /me/unlocks` again.',
});

/**
 * `GET /me/events`: the caller's live events as Server-Sent Events, while the app is open, so the
 * bell's dot changes at once instead of on the next read.
 */
export function events(deps: {
  readonly verifyToken: VerifyToken;
  readonly liveEvents: LiveEvents;
  readonly notices: Notices;
  readonly members: Members;
  readonly coachNames: CoachNames;
  readonly log: Log;
  readonly timing?: StreamTiming;
}) {
  const timing = deps.timing ?? TIMING;

  const route = createRoute({
    method: 'get',
    path: '/me/events',
    operationId: 'streamMyEvents',
    summary: 'The caller’s live events (Server-Sent Events)',
    description:
      'A `text/event-stream` that stays open while the app is. It starts with a `ready` event ' +
      '(data `LiveReady`); then each `notice` event (data `LiveNotice`, its SSE `id` the notice’s ' +
      'id) is a notice just told to the caller, as `GET /me/notices` will list it, and each ' +
      '`shelf` event (data `LiveShelf`) says the caller’s 商店街 may have changed (a store, piece, ' +
      'rule or switch, or one of their unlocks), so read `GET /me/unlocks` again. A line starting ' +
      'with `:` is a heartbeat, sent while it is quiet; skip it, and skip an event you don’t ' +
      `know. The server ends the stream after at most ${String(TIMING.maxAgeMs / 60_000)} ` +
      'minutes, or sooner when it restarts: reconnect after `retry`, then read the newest page ' +
      'of `GET /me/notices` and `GET /me/unlocks` again, since events sent while it was closed ' +
      'are not replayed.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: {
        description: 'The stream of events',
        content: {
          'text/event-stream': {
            schema: z.string().meta({ description: 'Server-Sent Events, as described above.' }),
          },
        },
      },
      401: problem('No bearer token, or not a valid one'),
      503: problem(
        'Sign-in can’t be checked right now, or live events can’t be heard ' +
          '(`LIVE_EVENTS_UNAVAILABLE`)',
      ),
    },
  });

  const app = new OpenAPIHono<SignedIn>();
  // The events' data, which no route's body names, so the app's generated types have them.
  app.openAPIRegistry.register('LiveReady', LiveReady);
  app.openAPIRegistry.register('LiveNotice', LiveNotice);
  app.openAPIRegistry.register('LiveShelf', LiveShelf);
  return app.openapi(route, async (c) => {
    const member = c.var.caller.userId;
    const told: number[] = [];
    // Several shelf changes before the stream writes are one read for the app.
    let shelfChanged = false;
    let ended = false;
    // Read through a function, since the listener and timers change it while the loop awaits.
    const isEnded = () => ended;
    let wake: (() => void) | undefined;
    const nudge = () => {
      wake?.();
      wake = undefined;
    };
    // Subscribed before the stream opens, so a failure answers as a problem (503).
    const stop = await deps.liveEvents.subscribe(member, {
      event: (event) => {
        if (event.kind === 'notice') told.push(event.id);
        else shelfChanged = true;
        nudge();
      },
      end: () => {
        ended = true;
        nudge();
      },
    });
    c.header('X-Accel-Buffering', 'no');
    return streamSSE(
      c,
      async (stream) => {
        stream.onAbort(() => {
          ended = true;
          nudge();
        });
        const tooOld = setTimeout(() => {
          ended = true;
          nudge();
        }, timing.maxAgeMs);
        try {
          await stream.writeSSE({
            event: 'ready',
            data: JSON.stringify({ version: 1 }),
            retry: RETRY_MS,
          });
          while (!isEnded()) {
            if (shelfChanged) {
              shelfChanged = false;
              await stream.writeSSE({ event: 'shelf', data: JSON.stringify({ version: 1 }) });
              continue;
            }
            const id = told.shift();
            if (id === undefined) {
              const beat = await new Promise<boolean>((resolve) => {
                const quiet = setTimeout(() => {
                  resolve(true);
                }, timing.heartbeatMs);
                wake = () => {
                  clearTimeout(quiet);
                  resolve(false);
                };
              });
              if (beat && !isEnded()) await stream.write(': ping\n\n');
              continue;
            }
            const notice = await noticeOf(member, id);
            if (notice === undefined) continue;
            await stream.writeSSE({
              event: 'notice',
              id: String(id),
              data: JSON.stringify({ version: 1, notice }),
            });
          }
        } finally {
          clearTimeout(tooOld);
          stop();
        }
      },
      async (error) => {
        // Ends the stream; the app reconnects and reads the notices again. A write the app's
        // leaving cut short is no failure.
        if (!isEnded()) deps.log.warn('live events stream failed', { error });
        await Promise.resolve();
      },
    );
  });

  /** The notice as the app reads it, or undefined for one this build can't read. */
  async function noticeOf(member: string, id: number) {
    const page = await deps.notices.page({
      member: MemberId.parse(member),
      before: NoticeId.parse(id + 1),
      limit: 1,
    });
    const notice = page.notices.find((each) => each.id === id);
    if (notice === undefined) return undefined;
    const [entry] = await noticeEntries(deps, { notices: [notice], broadcasts: page.broadcasts });
    return entry;
  }
}
