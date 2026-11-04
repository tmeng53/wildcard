import { isDeepStrictEqual } from 'node:util';

import {
  isRunning,
  type Broadcast,
  type BroadcastId,
  type BroadcastValue,
} from '../domain/broadcast.js';
import type { MemberId, NewNotice, Notice, NoticeId } from '../domain/notice.js';
import { NoticeNotFoundError } from '../errors.js';
import type { BroadcastStore, NoticeStore } from '../ports.js';

/** A page of the bell's history: see `Notices.page`. */
export interface NoticePage {
  readonly notices: readonly Notice[];
  /** The newest notice the member has seen, or `undefined` before they open the page. */
  readonly seenThrough?: NoticeId;
  /**
   * Where the next, older page starts, or `undefined` on the last. A page may hold fewer notices
   * than asked (or none) when it skipped some this build can't read; follow `next` regardless.
   */
  readonly next?: NoticeId;
  /** What each broadcast on the page says now, by id; one since lost is missing. */
  readonly broadcasts: ReadonlyMap<BroadcastId, Broadcast>;
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
  /**
   * The member's notices, newest first, `limit` at a time (at most `PAGE_LIMIT`). The newest
   * page (no `before`) first tells them every broadcast running now they weren't told yet.
   */
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

/** Broadcasts, for admins: notices written once for every member (`broadcast.ts`). */
export interface Broadcasts {
  /**
   * Saves what broadcast `id` says and when it runs, from `by`, unless it says that already;
   * answers with it as it is now, and whether this save changed it.
   */
  put(save: {
    readonly id: BroadcastId;
    readonly value: BroadcastValue;
    readonly by: MemberId;
  }): Promise<{ readonly broadcast: Broadcast; readonly changed: boolean }>;
  /** Every broadcast as it is now, the latest saved first. */
  list(): Promise<Broadcast[]>;
}

/**
 * Unlocks for `member` what `broadcast` gifts, before they are told it; answers whether it was
 * given, so a broadcast whose gifts failed is told on a later open instead, gifts and all.
 */
export type GiveGifts = (member: MemberId, broadcast: Broadcast) => Promise<boolean>;

export function createNotices(deps: {
  readonly store: NoticeStore;
  readonly broadcasts: BroadcastStore;
  /**
   * The time it is for `member`, which decides which broadcasts run for them: the wall clock, or
   * a date an admin pretends for a member to preview what is coming.
   */
  readonly clock: (member: MemberId) => Date | Promise<Date>;
  /** Gives a broadcast's gifts; left out where no broadcast is told. */
  readonly giveGifts?: GiveGifts;
}): Notices & Broadcasts {
  /** Tells the member the broadcasts running now they weren't told, those that started first first. */
  const tellRunning = async (member: MemberId) => {
    const now = await deps.clock(member);
    const running = (await deps.broadcasts.all())
      .filter(({ value }) => isRunning(value, now))
      .sort((a, b) => Date.parse(a.value.startsAt) - Date.parse(b.value.startsAt));
    if (running.length === 0) return;
    const told = await deps.store.toldBroadcasts(member);
    const fresh: BroadcastId[] = [];
    for (const broadcast of running) {
      if (told.has(broadcast.id)) continue;
      if (broadcast.value.gifts.length > 0) {
        // Gifts are kept like any unlock, so giving them twice keeps what was given once.
        if (deps.giveGifts === undefined || !(await deps.giveGifts(member, broadcast))) continue;
      }
      fresh.push(broadcast.id);
    }
    if (fresh.length > 0) await deps.store.tellBroadcasts(member, fresh);
  };
  return {
    async tell(notices) {
      if (notices.length === 0) return;
      await deps.store.add(notices);
    },

    async page({ member, before, limit }) {
      if (before === undefined) await tellRunning(member);
      const size = Math.min(Math.max(limit, 1), PAGE_LIMIT);
      const [{ notices, next }, seenThrough] = await Promise.all([
        deps.store.page({ member, ...(before === undefined ? {} : { before }), limit: size }),
        deps.store.seenThrough(member),
      ]);
      const named = notices.flatMap((notice) =>
        notice.kind === 'broadcast' ? [notice.subject.broadcast] : [],
      );
      const broadcasts = await deps.broadcasts.byId(named);
      return {
        notices,
        ...(seenThrough === undefined ? {} : { seenThrough }),
        ...(next === undefined ? {} : { next }),
        broadcasts: new Map(broadcasts.map((broadcast) => [broadcast.id, broadcast])),
      };
    },

    async markSeen(member, through) {
      const outcome = await deps.store.markSeen(member, through);
      if (outcome === 'unknown') throw new NoticeNotFoundError(through);
      return outcome;
    },

    async put({ id, value, by }) {
      const [now] = await deps.broadcasts.byId([id]);
      // A save that changes nothing writes no row. (Stored JSON keeps no key order.)
      if (now !== undefined && isDeepStrictEqual(now.value, value)) {
        return { broadcast: now, changed: false };
      }
      await deps.broadcasts.put({ id, value, by });
      const [saved] = await deps.broadcasts.byId([id]);
      if (saved === undefined) throw new Error(`broadcast ${id} was not saved`);
      return { broadcast: saved, changed: true };
    },

    list: () => deps.broadcasts.all(),
  };
}
