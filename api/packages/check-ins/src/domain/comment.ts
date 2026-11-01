import { z } from 'zod';

import type { MemberId } from './check-in.js';
import type { CommentText } from './text.js';

/** A comment's id, which the app picks, so saving it again is safe. */
export const CommentId = z.uuid().brand<'CommentId'>();
export type CommentId = z.infer<typeof CommentId>;

/**
 * What a member writes under a check-in (动态评论): its author or a teammate who can see it, one
 * level deep, any text up to 100 characters (Tracy, 2026-10-31). Written once and never changed;
 * its writer may delete it.
 */
export interface Comment {
  readonly id: CommentId;
  readonly member: MemberId;
  readonly text: CommentText;
  /** Whom it replies to (回复 Mia：…), when it does. */
  readonly replyTo?: MemberId | undefined;
  readonly commentedAt: Date;
}

/** Whether two writes of one comment id say the same thing, so the second is a retry. */
export function sameComment(
  a: Pick<Comment, 'member' | 'text' | 'replyTo'>,
  b: Pick<Comment, 'member' | 'text' | 'replyTo'>,
): boolean {
  return a.member === b.member && a.text === b.text && a.replyTo === b.replyTo;
}
