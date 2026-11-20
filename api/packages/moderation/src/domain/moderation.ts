import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/** A report's id, made by the app so a retry reports once. */
export const ReportId = z.uuid().brand<'ReportId'>();
export type ReportId = z.infer<typeof ReportId>;

/** What can be reported: a check-in, a comment under one, or the coach's reply or answer there. */
export const ReportKind = z.enum(['checkIn', 'comment', 'coachReply', 'coachAnswer']);
export type ReportKind = z.infer<typeof ReportKind>;

/** What the reporter saw, copied when they reported it, for whoever looks at the report. */
export interface ReportSnapshot {
  /** The caption, comment or coach's line; none when it had no words. */
  readonly words?: string | undefined;
  /** How many photos it had; a check-in's only. */
  readonly photos?: number | undefined;
}

/** One member's report of one thing under a check-in. */
export interface Report {
  readonly id: ReportId;
  readonly member: MemberId;
  readonly kind: ReportKind;
  readonly checkIn: string;
  /** The comment, coach reply or coach answer; none for the check-in itself. */
  readonly item?: string | undefined;
  /** Who wrote it, when a member did. */
  readonly author?: MemberId | undefined;
  readonly snapshot: ReportSnapshot;
  readonly at: Date;
}

/** A member someone blocked, and since when. */
export interface Blocked {
  readonly member: MemberId;
  readonly since: Date;
}

/** What a member no longer sees: everyone they blocked or who blocked them, and what they reported. */
export interface Hidden {
  /** Members on either side of a block with them. */
  readonly members: ReadonlySet<string>;
  readonly checkIns: ReadonlySet<string>;
  readonly comments: ReadonlySet<string>;
  /** By `coachReplyKey`: a coach's reply is its check-in's and coach's. */
  readonly coachReplies: ReadonlySet<string>;
  /** By the member's comment each answers. */
  readonly coachAnswers: ReadonlySet<string>;
}

/** The issue a report was filed as. */
export interface FiledIssue {
  readonly number: number;
  readonly url: string;
}

/** How a coach's reply is told apart in `Hidden`: one coach replies once to a check-in. */
export function coachReplyKey(checkIn: string, coach: string): string {
  return `${checkIn}/${coach}`;
}
