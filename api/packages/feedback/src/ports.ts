import type { Feedback, FeedbackId, FiledIssue, MemberId } from './domain/feedback.js';

/** Where messages and their issues are kept. A message is never changed once sent. */
export interface FeedbackStore {
  /**
   * Saves a message, unless one with its id is there already: then `unchanged` with the member
   * who sent that one.
   */
  add(
    feedback: Feedback,
  ): Promise<
    { readonly outcome: 'created' } | { readonly outcome: 'unchanged'; readonly member: MemberId }
  >;
  /** Who sent the message with this id, or `undefined` when there is none. */
  senderOf(id: FeedbackId): Promise<MemberId | undefined>;
  /** How many messages `member` sent after `since`. */
  countSince(member: MemberId, since: Date): Promise<number>;
  /** Messages sent before `before` that weren't filed yet, oldest first, at most `limit`. */
  unfiled(before: Date, limit: number): Promise<Feedback[]>;
  /** Keeps the issue a message was filed as; a second one for the same message changes nothing. */
  filed(filing: {
    readonly id: FeedbackId;
    readonly issue: FiledIssue;
    readonly at: Date;
  }): Promise<void>;
}

/** The current time. */
export type Clock = () => Date;
