import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import type { Members } from '@wildcard/members';
import { MemberId, NoticeId, type Notices } from '@wildcard/notices';
import { MemberId as ChatMember, SquadId as ChatSquad, type SquadChat } from '@wildcard/squad-chat';
import { streamSSE } from 'hono/streaming';

import { bodyVersion } from '../body-version.js';
import type { Log } from '../log.js';
import type { LiveEvent, LiveEvents, VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { NoticeEntry, noticeEntries, type CoachNames } from './notices.js';
import { ChatMessage, wireMessage } from './squad-chat.js';

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

export const LiveChat = z
  .strictObject({
    version: bodyVersion(1),
    squadId: z.uuid(),
    message: ChatMessage,
    quoted: ChatMessage.optional(),
  })
  .openapi('LiveChat', {
    description:
      'The `chat` event’s data: a message new to the chat, or whose reactions changed, as ' +
      '`GET /squads/{squadId}/chat/messages` lists it, with `quoted`, the message it replies to ' +
      'when it does and the caller can see it.',
  });

export const LiveChatDeleted = z
  .strictObject({ version: bodyVersion(1), squadId: z.uuid(), messageId: z.uuid() })
  .openapi('LiveChatDeleted', { description: 'The `chatDeleted` event’s data.' });

export const LiveCoachTyping = z
  .strictObject({
    version: bodyVersion(1),
    squadId: z.uuid(),
    coachId: z.string(),
    typing: z.boolean().meta({
      description:
        'Whether the coach is writing now. A `chat` event with its message ends it too, and so ' +
        'does a reconnect.',
    }),
  })
  .openapi('LiveCoachTyping', {
    description: 'The `coachTyping` event’s data: show the coach’s three dots while it is true.',
  });

/**
 * `GET /me/events`: the caller's live events as Server-Sent Events, while the app is open, so the
 * bell's dot (and later the coach's chat) changes at once instead of on the next read.
 */
export function events(deps: {
  readonly verifyToken: VerifyToken;
  readonly liveEvents: LiveEvents;
  readonly notices: Notices;
  readonly chat: Pick<SquadChat, 'seen'>;
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
      'id) is a notice just told to the caller, as `GET /me/notices` will list it. A line starting ' +
      'with `:` is a heartbeat, sent while it is quiet; skip it, and skip an event you don’t ' +
      `know. The server ends the stream after at most ${String(TIMING.maxAgeMs / 60_000)} ` +
      'minutes, or sooner when it restarts: reconnect after `retry`, then read the newest page ' +
      'of `GET /me/notices` and the open chat again, since events sent while it was closed are not ' +
      'replayed.',
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
  app.openAPIRegistry.register('LiveChat', LiveChat);
  app.openAPIRegistry.register('LiveChatDeleted', LiveChatDeleted);
  app.openAPIRegistry.register('LiveCoachTyping', LiveCoachTyping);
  return app.openapi(route, async (c) => {
    const member = c.var.caller.userId;
    const told: LiveEvent[] = [];
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
        told.push(event);
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
            const event = told.shift();
            if (event === undefined) {
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
            const message = await messageOf(member, event);
            if (message !== undefined) await stream.writeSSE(message);
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

  /** The SSE message an event is sent as, or undefined for one there is nothing to send of. */
  async function messageOf(
    member: string,
    event: LiveEvent,
  ): Promise<{ event: string; data: string; id?: string } | undefined> {
    switch (event.kind) {
      case 'notice': {
        const notice = await noticeOf(member, event.id);
        if (notice === undefined) return undefined;
        return {
          event: 'notice',
          id: String(event.id),
          data: JSON.stringify({ version: 1, notice }),
        };
      }
      case 'chat': {
        const seen = await deps.chat.seen({
          member: ChatMember.parse(member),
          squad: ChatSquad.parse(event.squad),
          seq: event.seq,
        });
        if (seen === undefined) return undefined;
        return {
          event: 'chat',
          data: JSON.stringify({
            version: 1,
            squadId: event.squad,
            message: wireMessage(seen.message),
            ...(seen.quoted === undefined ? {} : { quoted: wireMessage(seen.quoted) }),
          }),
        };
      }
      case 'chatDeleted':
        return {
          event: 'chatDeleted',
          data: JSON.stringify({ version: 1, squadId: event.squad, messageId: event.message }),
        };
      case 'coachTyping':
        return {
          event: 'coachTyping',
          data: JSON.stringify({
            version: 1,
            squadId: event.squad,
            coachId: event.coach,
            typing: event.typing,
          }),
        };
    }
  }

  /** The notice as the app reads it, or undefined for one this build can't read. */
  async function noticeOf(member: string, id: number) {
    const page = await deps.notices.page({
      member: MemberId.parse(member),
      before: NoticeId.parse(id + 1),
      limit: 1,
    });
    const notice = page.notices.find((each) => each.id === id);
    if (notice === undefined) return undefined;
    const [entry] = await noticeEntries(deps, [notice]);
    return entry;
  }
}
