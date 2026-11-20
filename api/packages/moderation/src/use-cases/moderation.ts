import type {
  Blocked,
  FiledIssue,
  Hidden,
  MemberId,
  Report,
  ReportId,
} from '../domain/moderation.js';
import { BlockSelfError, ReportIdTakenError } from '../errors.js';
import type { Clock, ModerationStore } from '../ports.js';

/** Blocking and reporting (App Review guideline 1.2): what members keep away from themselves. */
export interface Moderation {
  /** The members `member` blocks, newest first. */
  blocked(member: MemberId): Promise<Blocked[]>;
  /** `member` blocks `other`: neither sees the other's posts, comments or reactions. Again changes nothing. */
  block(input: { readonly member: MemberId; readonly other: MemberId }): Promise<void>;
  /** `member` stops blocking `other`. Nothing when they didn't. */
  unblock(input: { readonly member: MemberId; readonly other: MemberId }): Promise<void>;
  /** What `member` no longer sees. */
  hiddenFor(member: MemberId): Promise<Hidden>;
  /** Of `members`, those on either side of a block with `member`, who aren't told of each other. */
  blockedAmong(member: MemberId, members: readonly MemberId[]): Promise<Set<string>>;
  /**
   * Keeps a report; the same id or the same thing again returns the one that stands. `fresh`
   * says this call made it, so it is filed once.
   */
  report(report: Omit<Report, 'at'>): Promise<{ readonly report: Report; readonly fresh: boolean }>;
  /** Reports at least `ageMs` old that weren't filed yet, oldest first, at most `limit`. */
  toFile(ageMs: number, limit: number): Promise<Report[]>;
  /** Keeps the issue a report was filed as. */
  filed(id: ReportId, issue: FiledIssue): Promise<void>;
}

export function createModeration(deps: {
  readonly store: ModerationStore;
  readonly clock: Clock;
}): Moderation {
  const { store, clock } = deps;
  return {
    blocked: (member) => store.blockedBy(member),

    async block({ member, other }) {
      if (member === other) throw new BlockSelfError();
      const now = await store.blockedBy(member);
      if (now.some((each) => each.member === other)) return;
      await store.log({ member, other, kind: 'blocked', at: clock() });
    },

    async unblock({ member, other }) {
      const now = await store.blockedBy(member);
      if (!now.some((each) => each.member === other)) return;
      await store.log({ member, other, kind: 'unblocked', at: clock() });
    },

    hiddenFor: (member) => store.hiddenFor(member),

    blockedAmong: (member, members) =>
      members.length === 0 ? Promise.resolve(new Set()) : store.blockedAmong(member, members),

    async report(input) {
      const saved = await store.report({ ...input, at: clock() });
      if (saved.report.member !== input.member) throw new ReportIdTakenError(input.id);
      return saved;
    },

    toFile: (ageMs, limit) => store.unfiled(new Date(clock().getTime() - ageMs), limit),

    filed: (id, issue) => store.filed({ id, issue, at: clock() }),
  };
}
