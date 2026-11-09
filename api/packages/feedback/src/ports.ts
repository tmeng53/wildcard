import type {
  Adoption,
  AdoptionKind,
  Feedback,
  FeedbackId,
  FiledIssue,
  MemberId,
} from './domain/feedback.js';

/** Where messages and their issues are kept. A message is never changed once sent. */
export interface FeedbackStore {
  /**
   * Saves a message, unless one with its id is there already: then `unchanged` with the member
   * who sent that one. A new one is refused as `limited` once its member sent `limit` after
   * `since`; one member's messages are counted and saved one at a time, so a burst can't pass it.
   */
  add(
    feedback: Feedback,
    quota: { readonly limit: number; readonly since: Date },
  ): Promise<
    | { readonly outcome: 'created' }
    | { readonly outcome: 'unchanged'; readonly member: MemberId }
    | { readonly outcome: 'limited' }
  >;
  /** Messages sent before `before` that weren't filed yet, oldest first, at most `limit`. */
  unfiled(before: Date, limit: number): Promise<Feedback[]>;
  /** Keeps the issue a message was filed as; a second one for the same message changes nothing. */
  filed(filing: {
    readonly id: FeedbackId;
    readonly issue: FiledIssue;
    readonly at: Date;
  }): Promise<void>;
  /**
   * Keeps that `admin` adopted the message as `kind`, unless it was adopted before: then the
   * first adoption stands and `fresh` is false. `undefined` when there is no such message.
   */
  adopt(adoption: {
    readonly feedback: FeedbackId;
    readonly kind: AdoptionKind;
    readonly admin: MemberId;
    readonly at: Date;
  }): Promise<{ readonly adoption: Adoption; readonly fresh: boolean } | undefined>;
}

/** The current time. */
export type Clock = () => Date;
