import { describe, expect, it } from 'vitest';

import { jobsTokenScheduler } from '../adapters/scheduler.js';
import type { EventHandlers, ServerEvent } from '../events.js';
import { createLog } from '../log.js';
import { eventPushes } from './jobs.js';

const token = 'a-local-jobs-token-that-is-long-enough-1234';
const commented: ServerEvent = {
  version: 1,
  kind: 'comment.created',
  checkIn: '00000000-0000-4000-8000-000000000001',
  comment: '00000000-0000-4000-8000-000000000002',
  commenter: '00000000-0000-4000-8000-000000000003',
  author: '00000000-0000-4000-8000-000000000004',
  text: '我下周怎么练',
  mentions: [],
  coach: 'maotou',
  squads: ['00000000-0000-4000-8000-000000000005'],
};

function app(answer: EventHandlers['coach-answer']) {
  const answered: ServerEvent[] = [];
  const handlers: EventHandlers = {
    'coach-look': () => Promise.resolve(),
    'comment-push': () => Promise.resolve(),
    'coach-welcome': () => Promise.resolve(),
    'coach-answer': async (event) => {
      answered.push(event);
      await answer(event);
    },
  };
  const routes = eventPushes({
    isScheduler: jobsTokenScheduler(token),
    events: handlers,
    log: createLog(() => undefined),
  });
  routes.onError((_, c) => c.body(null, 500));
  const push = (
    subscriber: string,
    { data, authorization = `Bearer ${token}` }: { data: string; authorization?: string },
  ) =>
    routes.request(`/jobs/events/${subscriber}`, {
      method: 'POST',
      headers: { authorization, 'content-type': 'application/json' },
      body: JSON.stringify({
        message: { data, messageId: '1', attributes: { kind: 'comment.created' } },
        subscription: `projects/p/subscriptions/${subscriber}`,
      }),
    });
  return { answered, push };
}

const encoded = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64');

describe('events Pub/Sub pushes', () => {
  it('reach their subscriber, signed as the scheduler', async () => {
    const { answered, push } = app(() => Promise.resolve());
    expect(
      (await push('coach-answer', { data: encoded(commented), authorization: 'Bearer wrong' }))
        .status,
    ).not.toBe(204);
    expect(answered).toStrictEqual([]);
    expect((await push('coach-answer', { data: encoded(commented) })).status).toBe(204);
    expect(answered).toStrictEqual([commented]);
  });

  it('are taken without work when unreadable, so Pub/Sub stops trying', async () => {
    const { answered, push } = app(() => Promise.resolve());
    expect((await push('coach-answer', { data: 'not base64 json' })).status).toBe(204);
    expect(
      (await push('coach-answer', { data: encoded({ ...commented, kind: 'other' }) })).status,
    ).toBe(204);
    expect(answered).toStrictEqual([]);
  });

  it('answer an error when the subscriber fails, so Pub/Sub tries again', async () => {
    const { push } = app(() => Promise.reject(new Error('the coach is down')));
    expect((await push('coach-answer', { data: encoded(commented) })).status).toBe(500);
  });

  it('are refused for a subscriber that doesn’t exist', async () => {
    const { push } = app(() => Promise.resolve());
    expect((await push('nobody', { data: encoded(commented) })).status).not.toBe(204);
  });
});
