import { randomUUID } from 'node:crypto';

import type { CoachFeedback } from '@wildcard/coach';
import { FeedbackId, MemberId, type FeedbackInbox } from '@wildcard/feedback';

import { fileFeedback, type FeedbackIssueDependencies } from './feedback-issues.js';

/**
 * The coach passing on what a member asked of the app (Tracy, 2026-11-12): saved as feedback
 * from that member, counted in their day's limit like 意见反馈, and filed as an issue at once
 * (a message that can't be filed now waits for the jobs). Why not, when it was refused.
 */
export function coachFeedback(
  deps: FeedbackIssueDependencies & {
    readonly feedback: Pick<FeedbackInbox, 'send' | 'toFile' | 'filed'>;
  },
): CoachFeedback {
  return async ({ squad, coach, member, checkIn, comment, kind, text, quote }) => {
    try {
      const { outcome, feedback } = await deps.feedback.send({
        id: FeedbackId.parse(randomUUID()),
        member: MemberId.parse(member),
        kind,
        body: text,
        source: {
          from: 'coach',
          coach,
          squad,
          checkIn,
          ...(comment === undefined ? {} : { comment }),
          quote,
        },
      });
      if (outcome === 'created') await fileFeedback(deps, feedback);
      return undefined;
    } catch (error) {
      return error instanceof Error ? error.message : String(error);
    }
  };
}
