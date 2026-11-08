import { describe, expect, it } from 'vitest';

import {
  deliver,
  inProcessEvents,
  topicOf,
  type EventHandlers,
  type ServerEvent,
} from './events.js';
import { createLog } from './log.js';

const [checkIn, comment, writer, author, squad] = [
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000003',
  '00000000-0000-4000-8000-000000000004',
  '00000000-0000-4000-8000-000000000005',
];
const checkedIn: ServerEvent = { version: 1, kind: 'check-in.created', checkIn, squads: [squad] };
const commented: ServerEvent = {
  version: 1,
  kind: 'comment.created',
  checkIn,
  comment,
  commenter: writer,
  author,
  text: '我下周怎么练',
  mentions: [],
  coach: 'maotou',
  squads: [squad],
};

/** Handlers that note which ran, on which event. */
function noting(fail?: keyof EventHandlers) {
  const ran: string[] = [];
  const run = (name: keyof EventHandlers) => (event: ServerEvent) => {
    ran.push(`${name}:${event.kind}`);
    return name === fail ? Promise.reject(new Error('down')) : Promise.resolve();
  };
  const handlers: EventHandlers = {
    'coach-look': run('coach-look'),
    'comment-push': run('comment-push'),
    'coach-answer': run('coach-answer'),
  };
  return { ran, handlers };
}

describe('events', () => {
  it('go to a topic named after their kind', () => {
    expect(topicOf('check-in.created')).toBe('check-in-created');
    expect(topicOf('comment.created')).toBe('comment-created');
  });

  it('reach only the subscribers of their kind', async () => {
    const { ran, handlers } = noting();
    expect(await deliver(handlers, { subscriber: 'coach-answer', event: commented })).toBe(true);
    expect(await deliver(handlers, { subscriber: 'coach-look', event: commented })).toBe(false);
    expect(ran).toStrictEqual(['coach-answer:comment.created']);
  });

  it('run every subscriber in the request without Pub/Sub, and log one that fails', async () => {
    const { ran, handlers } = noting('comment-push');
    const lines: string[] = [];
    const publish = inProcessEvents(
      handlers,
      createLog((line) => lines.push(line)),
    );
    await publish(commented);
    await publish(checkedIn);
    expect(ran).toStrictEqual([
      'comment-push:comment.created',
      'coach-answer:comment.created',
      'coach-look:check-in.created',
    ]);
    expect(lines.some((line) => line.includes('event subscriber failed'))).toBe(true);
  });
});
