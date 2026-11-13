import {
  type Adoption,
  type AdoptionKind,
  FEEDBACK_MAX_LENGTH,
  FeedbackBody,
  FEEDBACK_MAX_SCREENSHOTS,
  type Feedback,
  type FeedbackId,
  type FeedbackKind,
  type FeedbackSource,
  type FiledIssue,
  type MemberId,
} from '../domain/feedback.js';
import {
  FeedbackIdTakenError,
  FeedbackInvalidError,
  FeedbackLimitError,
  FeedbackMissingError,
} from '../errors.js';
import type { Clock, FeedbackStore } from '../ports.js';

export interface SendFeedbackInput {
  readonly id: FeedbackId;
  readonly member: MemberId;
  readonly kind: FeedbackKind;
  readonly body: string;
  readonly source: FeedbackSource;
}

/**
 * 意见反馈: members' messages to us, from the app or passed on by their coach, each filed as an
 * issue where agents pick it up.
 */
export interface FeedbackInbox {
  /**
   * Saves a message. The same id again is `unchanged`, so a retry is safe. Throws
   * `FeedbackInvalidError` for an empty or too long message, too many screenshots, or a coach's
   * without the member's words,
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

/** Which messages we used, for admins: only one adopts a message, after checking it. */
export interface FeedbackAdoptions {
  /**
   * Keeps that `admin` adopted message `id` as `kind`; adopting it again keeps the first, with
   * `fresh` false. Throws `FeedbackMissingError` for a message that isn't there.
   */
  adopt(request: {
    readonly id: FeedbackId;
    readonly kind: AdoptionKind;
    readonly admin: MemberId;
  }): Promise<{ readonly adoption: Adoption; readonly fresh: boolean }>;
}

export function createFeedbackAdoptions(deps: {
  readonly store: Pick<FeedbackStore, 'adopt'>;
  readonly clock: Clock;
}): FeedbackAdoptions {
  return {
    async adopt({ id, kind, admin }) {
      const kept = await deps.store.adopt({ feedback: id, kind, admin, at: deps.clock() });
      if (kept === undefined) throw new FeedbackMissingError(id);
      return kept;
    },
  };
}

/** How many messages a member may send in a day, so a stuck button can't flood the tracker. */
export const FEEDBACK_DAILY_LIMIT = 10;

const DAY_MS = 24 * 60 * 60 * 1000;

export function createFeedbackInbox(deps: {
  readonly store: FeedbackStore;
  readonly clock: Clock;
}): FeedbackInbox {
  return {
    async send({ id, member, kind, body, source }) {
      const words = FeedbackBody.safeParse(body);
      if (!words.success) {
        throw new FeedbackInvalidError(
          `A message has 1 to ${String(FEEDBACK_MAX_LENGTH)} characters.`,
        );
      }
      if (source.from === 'app' && source.screenshots.length > FEEDBACK_MAX_SCREENSHOTS) {
        throw new FeedbackInvalidError(
          `A message has at most ${String(FEEDBACK_MAX_SCREENSHOTS)} screenshots.`,
        );
      }
      if (source.from === 'coach' && source.quote.trim() === '') {
        throw new FeedbackInvalidError("A coach's message quotes the member's own words.");
      }
      const at = deps.clock();
      const feedback: Feedback = { id, member, kind, body: words.data, source, at };
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
