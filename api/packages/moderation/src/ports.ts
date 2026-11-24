import type {
  Blocked,
  FiledIssue,
  Hidden,
  MemberId,
  Report,
  ReportId,
} from './domain/moderation.js';

/** Where blocks and reports are kept: a log of every block and unblock, and every report. */
export interface ModerationStore {
  /** The members `member` blocks now, newest first. */
  blockedBy(member: MemberId): Promise<Blocked[]>;
  /** Logs that `member` blocked (or unblocked) `other` at `at`. */
  log(entry: {
    readonly member: MemberId;
    readonly other: MemberId;
    readonly kind: 'blocked' | 'unblocked';
    readonly at: Date;
  }): Promise<void>;
  /** What `member` no longer sees. */
  hiddenFor(member: MemberId): Promise<Hidden>;
  /** Of `members`, those on either side of a block with `member`. */
  blockedAmong(member: MemberId, members: readonly MemberId[]): Promise<Set<string>>;
  /**
   * Saves a report, unless one with its id is there already or `member` reported the same thing
   * before: then the one that stands.
   */
  report(report: Report): Promise<{ readonly report: Report; readonly fresh: boolean }>;
  /** Reports made before `before` that weren't filed yet, oldest first, at most `limit`. */
  unfiled(before: Date, limit: number): Promise<Report[]>;
  /** Keeps the issue a report was filed as; a second one for the same report changes nothing. */
  filed(filing: {
    readonly id: ReportId;
    readonly issue: FiledIssue;
    readonly at: Date;
  }): Promise<void>;
}

/** The current time. */
export type Clock = () => Date;
