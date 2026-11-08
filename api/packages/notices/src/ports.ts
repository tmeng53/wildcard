import type { Broadcast, BroadcastId, BroadcastValue } from './domain/broadcast.js';
import type { MemberId, NewNotice, Notice, NoticeId } from './domain/notice.js';

/** Where notices and how far each member read them are kept. Neither is ever changed. */
export interface NoticeStore {
  /**
   * Writes `notices`, in order, and answers with the members whose notice this call wrote; one
   * the database already holds (a comment's, told once a member) is left out, never written twice.
   */
  add(notices: readonly NewNotice[]): Promise<readonly MemberId[]>;
  /** The broadcasts the member was told, by id. */
  toldBroadcasts(member: MemberId): Promise<ReadonlySet<BroadcastId>>;
  /**
   * Tells the member each broadcast they weren't told yet, in order, and answers with the ones
   * this call told; one told meanwhile by another call is left out, never told twice.
   */
  tellBroadcasts(member: MemberId, broadcasts: readonly BroadcastId[]): Promise<BroadcastId[]>;
  /**
   * The member's notices older than `before` (all when left out), newest first: `limit` rows at
   * most, less any of a kind or shape this build can't read, which are left out. `next` is the
   * oldest row's id when older rows remain, so a page of skipped rows never ends the history.
   */
  page(query: {
    readonly member: MemberId;
    readonly before?: NoticeId;
    readonly limit: number;
  }): Promise<{ readonly notices: Notice[]; readonly next?: NoticeId }>;
  /** The newest notice the member has seen, or `undefined` before they open the page. */
  seenThrough(member: MemberId): Promise<NoticeId | undefined>;
  /**
   * Records that the member has seen up to `through`, unless they had seen as far already;
   * `unknown` when `through` isn't one of their notices.
   */
  markSeen(member: MemberId, through: NoticeId): Promise<'moved' | 'unchanged' | 'unknown'>;
}

/** Where broadcasts are kept: each save a new row, the newest for an id what it says now. */
export interface BroadcastStore {
  /** Saves `value` as what broadcast `id` says from now on. */
  put(save: { id: BroadcastId; value: BroadcastValue; by: MemberId }): Promise<void>;
  /** Every broadcast as it is now, the latest saved first. */
  all(): Promise<Broadcast[]>;
  /** The broadcasts with these ids as they are now; one that doesn't exist is left out. */
  byId(ids: readonly BroadcastId[]): Promise<Broadcast[]>;
}
