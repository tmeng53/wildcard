import { CoachId, SquadId } from '@wildcard/coach';
import type { FeedbackInbox } from '@wildcard/feedback';
import { describe, expect, it } from 'vitest';

import { coachFeedback } from './coach-feedback.js';

type Send = FeedbackInbox['send'];

describe('coachFeedback', () => {
  it('saves what one wake passes on under one id, so a wake run twice passes it on once', async () => {
    const ids: string[] = [];
    const send: Send = (message) => {
      ids.push(message.id);
      return Promise.reject(new Error('stop after the id'));
    };
    const relay = coachFeedback({
      feedback: { send, toFile: () => Promise.resolve([]), filed: () => Promise.resolve() },
      issues: undefined,
      photos: { createViewUrls: () => Promise.resolve(new Map()) },
      log: { info: () => undefined, warn: () => undefined, error: () => undefined },
    });
    const asked = (wake: number) =>
      relay({
        wake,
        squad: SquadId.parse('00000000-0000-4000-8000-000000000003'),
        coach: CoachId.parse('maotou'),
        member: '00000000-0000-4000-8000-000000000002',
        checkIn: '00000000-0000-4000-8000-000000000004',
        kind: 'idea',
        text: '想在动态上标地点',
        quote: '要是能 tag 地点就好了',
      });
    await expect(asked(7)).resolves.toBe('stop after the id');
    await asked(7);
    await asked(8);
    expect(ids[0]).toBe(ids[1]);
    expect(ids[2]).not.toBe(ids[0]);
    expect(ids[0]).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}$/u);
  });
});
