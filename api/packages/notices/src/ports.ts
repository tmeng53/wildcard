import type { MemberId, NewNotice, Notice, NoticeId } from './domain/notice.js';

/** Where notices and how far each member read them are kept. Neither is ever changed. */
export interface NoticeStore {
  /** Writes `notices`, in order. */
  add(notices: readonly NewNotice[]): Promise<void>;
  /** The member's notices older than `before` (all when left out), newest first, at most `limit`. */
  page(query: {
    readonly member: MemberId;
    readonly before?: NoticeId;
    readonly limit: number;
  }): Promise<Notice[]>;
  /** The newest notice the member has seen, or `undefined` before they open the page. */
  seenThrough(member: MemberId): Promise<NoticeId | undefined>;
  /**
   * Records that the member has seen up to `through`, unless they had seen as far already;
   * `unknown` when `through` isn't one of their notices.
   */
  markSeen(member: MemberId, through: NoticeId): Promise<'moved' | 'unchanged' | 'unknown'>;
}
