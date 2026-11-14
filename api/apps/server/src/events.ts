import { setTimeout as wait } from 'node:timers/promises';

import { AUDIENCE_MAX } from '@wildcard/check-ins';
import { z } from 'zod';

import type { Log } from './log.js';

/**
 * What happened, for the work that follows it after the request has answered: a request saves,
 * publishes an event and answers; each subscriber (a coach looking at a post, the push a 训练
 * sends the squad, the pushes a comment sends) runs on its own. Hosted, each kind is a Pub/Sub topic and each subscriber a push
 * subscription to `/jobs/events/<subscriber>` (`scripts/gcp-setup.sh`); elsewhere they run in
 * the request (`inProcessEvents`). Delivery is at least once, so every subscriber is safe to run
 * twice.
 */

const Id = z.uuid();

/** A check-in just made and shared to these squads. */
export const CheckInCreated = z.strictObject({
  version: z.literal(1),
  kind: z.literal('check-in.created'),
  checkIn: Id,
  squads: z.array(Id).min(1).max(AUDIENCE_MAX),
});
export type CheckInCreated = z.infer<typeof CheckInCreated>;

/**
 * A 训练 saved or edited naming squadmates it was done with (一起练): each is told once a post,
 * so an edit sends them all again and only those new to it hear.
 */
export const TrainedWithNamed = z.strictObject({
  version: z.literal(1),
  kind: z.literal('check-in.trained-with'),
  checkIn: Id,
  /** Who posted it. */
  author: Id,
  members: z.array(Id).min(1).max(7),
});
export type TrainedWithNamed = z.infer<typeof TrainedWithNamed>;

/** A comment just written, with whom it concerns. */
export const CommentCreated = z.strictObject({
  version: z.literal(1),
  kind: z.literal('comment.created'),
  checkIn: Id,
  comment: Id,
  /** Who wrote it. */
  commenter: Id,
  /** Who posted the check-in. */
  author: Id,
  text: z.string().min(1).max(1000),
  replyTo: Id.optional(),
  mentions: z.array(Id).max(8),
  /** The coach it replies to or @s, which answers it. */
  coach: z.string().max(40).optional(),
  /** The squads the writer sees the check-in through. */
  squads: z.array(Id).max(AUDIENCE_MAX),
});
export type CommentCreated = z.infer<typeof CommentCreated>;

/** A member who just joined a squad. */
export const SquadJoined = z.strictObject({
  version: z.literal(1),
  kind: z.literal('squad.joined'),
  squad: Id,
  member: Id,
});
export type SquadJoined = z.infer<typeof SquadJoined>;

export const ServerEvent = z.discriminatedUnion('kind', [
  CheckInCreated,
  CommentCreated,
  SquadJoined,
  TrainedWithNamed,
]);
export type ServerEvent = z.infer<typeof ServerEvent>;

/**
 * Publishes an event once what it tells of is saved, for the work that follows it. Never throws:
 * an event that can't go out is logged.
 */
export type PublishEvent = (event: ServerEvent) => Promise<void>;

/** Who reacts to events: each a Pub/Sub subscription on the topic of its kind. */
export const Subscriber = z.enum([
  'coach-look',
  'teammate-push',
  'comment-push',
  'coach-answer',
  'coach-welcome',
  'trained-with-push',
]);
export type Subscriber = z.infer<typeof Subscriber>;

/** The kind of event each subscriber takes. */
export const SUBSCRIBERS = {
  'coach-look': 'check-in.created',
  'teammate-push': 'check-in.created',
  'comment-push': 'comment.created',
  'coach-answer': 'comment.created',
  'trained-with-push': 'check-in.trained-with',
  'coach-welcome': 'squad.joined',
} as const satisfies Record<Subscriber, ServerEvent['kind']>;

/** What each subscriber does with its kind of event. Throwing has Pub/Sub deliver it again. */
export type EventHandlers = {
  readonly [S in Subscriber]: (
    event: Extract<ServerEvent, { kind: (typeof SUBSCRIBERS)[S] }>,
  ) => Promise<void>;
};

/** The Pub/Sub topic of a kind of event: `check-in.created` is `check-in-created`. */
export const topicOf = (kind: ServerEvent['kind']): string => kind.replaceAll('.', '-');

/** Runs one subscriber on an event; false when the event isn't of its kind. */
export async function deliver(
  handlers: EventHandlers,
  { subscriber, event }: { readonly subscriber: Subscriber; readonly event: ServerEvent },
): Promise<boolean> {
  if (SUBSCRIBERS[subscriber] !== event.kind) return false;
  switch (event.kind) {
    case 'check-in.created':
      await (subscriber === 'teammate-push'
        ? handlers['teammate-push'](event)
        : handlers['coach-look'](event));
      return true;
    case 'comment.created':
      await (subscriber === 'coach-answer'
        ? handlers['coach-answer'](event)
        : handlers['comment-push'](event));
      return true;
    case 'check-in.trained-with':
      await handlers['trained-with-push'](event);
      return true;
    case 'squad.joined':
      await handlers['coach-welcome'](event);
      return true;
  }
}

/**
 * How long a request waits for the work an event starts when it runs in the request, inside the
 * app's 15-second request timeout; the rest is the coach job's to finish.
 */
const IN_REQUEST_WAIT_MS = 8_000;

/**
 * Events without Pub/Sub (local stacks and tests; never the hosted server): every subscriber of
 * the event runs in the request, side by side, which waits at most `IN_REQUEST_WAIT_MS`. A
 * failure is logged; what the request saved stays saved.
 */
export function inProcessEvents(handlers: EventHandlers, log: Log): PublishEvent {
  return async (event) => {
    const subscribers = Subscriber.options.filter((each) => SUBSCRIBERS[each] === event.kind);
    const stop = new AbortController();
    const late = wait(IN_REQUEST_WAIT_MS, 'late' as const, { signal: stop.signal }).catch(
      () => undefined,
    );
    const working = Promise.all(
      subscribers.map((subscriber) =>
        deliver(handlers, { subscriber, event }).catch((error: unknown) => {
          log.error('event subscriber failed', { kind: event.kind, subscriber, error });
        }),
      ),
    );
    const outcome = await Promise.race([working, late]);
    stop.abort();
    if (outcome === 'late') log.warn('event subscribers still running', { kind: event.kind });
  };
}
