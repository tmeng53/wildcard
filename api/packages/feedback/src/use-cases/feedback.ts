import {
  FEEDBACK_MAX_LENGTH,
  FeedbackBody,
  FEEDBACK_MAX_SCREENSHOTS,
  type AppInfo,
  type Feedback,
  type FeedbackId,
  type FeedbackKind,
  type FiledIssue,
  type MemberId,
} from '../domain/feedback.js';
import { FeedbackIdTakenError, FeedbackInvalidError, FeedbackLimitError } from '../errors.js';
import type { Clock, FeedbackStore } from '../ports.js';

export interface SendFeedbackInput {
  readonly id: FeedbackId;
  readonly member: MemberId;
  readonly kind: FeedbackKind;
  readonly body: string;
  readonly screenshots: readonly string[];
  readonly app: AppInfo;
}

/** 意见反馈: members' messages to us, each filed as an issue where agents pick it up. */
export interface FeedbackInbox {
  /**
   * Saves a message. The same id again is `unchanged`, so a retry is safe. Throws
   * `FeedbackInvalidError` for an empty or too long message or too many screenshots,
   * `FeedbackLimitError` past the day's limit and `FeedbackIdTakenError` for another member's id.
   */
  send(
    input: SendFeedbackInput,
  ): Promise<{ readonly outcome: 'created' | 'unchanged'; readonly feedback: Feedback }>;
  /** Messages still to file that were sent at least `olderThanMs` ago, oldest first. */
  toFile(olderThanMs: number, limit: number): Promise<Feedback[]>;
  /** Keeps the issue a message was filed as. */
  filed(id: FeedbackId, issue: FiledIssue): Promise<void>;
}

/** How many messages a member may send in a day, so a stuck button can't flood the tracker. */
export const FEEDBACK_DAILY_LIMIT = 10;

const DAY_MS = 24 * 60 * 60 * 1000;

export function createFeedbackInbox(deps: {
  readonly store: FeedbackStore;
  readonly clock: Clock;
}): FeedbackInbox {
  return {
    async send({ id, member, kind, body, screenshots, app }) {
      const words = FeedbackBody.safeParse(body);
      if (!words.success) {
        throw new FeedbackInvalidError(
          `A message has 1 to ${String(FEEDBACK_MAX_LENGTH)} characters.`,
        );
      }
      if (screenshots.length > FEEDBACK_MAX_SCREENSHOTS) {
        throw new FeedbackInvalidError(
          `A message has at most ${String(FEEDBACK_MAX_SCREENSHOTS)} screenshots.`,
        );
      }
      const at = deps.clock();
      const feedback: Feedback = { id, member, kind, body: words.data, screenshots, app, at };
      // A retry of a message already saved passes, whatever the limit.
      const saved = await deps.store.add(feedback, {
        limit: FEEDBACK_DAILY_LIMIT,
        since: new Date(at.getTime() - DAY_MS),
      });
      if (saved.outcome === 'limited') throw new FeedbackLimitError(FEEDBACK_DAILY_LIMIT);
      if (saved.outcome === 'unchanged' && saved.member !== member) {
        throw new FeedbackIdTakenError(id);
      }
      return { outcome: saved.outcome, feedback };
    },

    toFile(olderThanMs, limit) {
      return deps.store.unfiled(new Date(deps.clock().getTime() - olderThanMs), limit);
    },

    filed(id, issue) {
      return deps.store.filed({ id, issue, at: deps.clock() });
    },
  };
}
