import type { MemberId, NewNotice, Notice, NoticeId } from '../domain/notice.js';
import { NoticeNotFoundError } from '../errors.js';
import type { NoticeStore } from '../ports.js';

/** A page of the bell's history: see `Notices.page`. */
export interface NoticePage {
  readonly notices: readonly Notice[];
  /** The newest notice the member has seen, or `undefined` before they open the page. */
  readonly seenThrough?: NoticeId;
  /** Where the next, older page starts, or `undefined` on the last. */
  readonly next?: NoticeId;
}

/** The most notices a page holds. */
export const PAGE_LIMIT = 50;

/**
 * The notices members were told (通知, the bell on 动态): what was pushed or shown to them, kept
 * forever so one missed can be found again, and how far each member has read.
 */
export interface Notices {
  /** Writes notices told now. Never changes one already written. */
  tell(notices: readonly NewNotice[]): Promise<void>;
  /** The member's notices, newest first, `limit` at a time (at most `PAGE_LIMIT`). */
  page(query: {
    readonly member: MemberId;
    readonly before?: NoticeId;
    readonly limit: number;
  }): Promise<NoticePage>;
  /**
   * Marks the member's notices up to `through` seen. Never goes back: an older id, or the same
   * again, is `unchanged`, so a retry is safe.
   *
   * @throws {NoticeNotFoundError} When `through` isn't one of the member's notices.
   */
  markSeen(member: MemberId, through: NoticeId): Promise<'moved' | 'unchanged'>;
}

export function createNotices(deps: { readonly store: NoticeStore }): Notices {
  return {
    async tell(notices) {
      if (notices.length === 0) return;
      await deps.store.add(notices);
    },

    async page({ member, before, limit }) {
      const size = Math.min(Math.max(limit, 1), PAGE_LIMIT);
      // One more than the page, to know whether another follows.
      const [rows, seenThrough] = await Promise.all([
        deps.store.page({ member, ...(before === undefined ? {} : { before }), limit: size + 1 }),
        deps.store.seenThrough(member),
      ]);
      const notices = rows.slice(0, size);
      const last = notices.at(-1);
      return {
        notices,
        ...(seenThrough === undefined ? {} : { seenThrough }),
        ...(rows.length > size && last !== undefined ? { next: last.id } : {}),
      };
    },

    async markSeen(member, through) {
      const outcome = await deps.store.markSeen(member, through);
      if (outcome === 'unknown') throw new NoticeNotFoundError(through);
      return outcome;
    },
  };
}
