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
  /**
   * The coach it replies to (回复 毛头：…), by the coach's id, when it does: one who said
   * something under the check-in. Never with `replyTo`.
   */
  readonly replyToCoach?: string | undefined;
  /**
   * Whom it @s, in the order written (feedback #58): up to `MAX_MENTIONS` people who can see the
   * check-in, never its writer. Left out when it @s no one.
   */
  readonly mentions?: readonly MemberId[] | undefined;
  /** The coach it @s (@毛头), by the coach's id, when it does: the coach answers it. */
  readonly mentionsCoach?: string | undefined;
  readonly commentedAt: Date;
}

/** How many people one comment may @ (Tracy, 2026-11-05). */
export const MAX_MENTIONS = 8;

type Said = Pick<Comment, 'member' | 'text' | 'replyTo' | 'replyToCoach' | 'mentions' | 'mentionsCoach'>;

/** Whether two writes of one comment id say the same thing, so the second is a retry. */
export function sameComment(a: Said, b: Said): boolean {
  const aMentions = a.mentions ?? [];
  const bMentions = b.mentions ?? [];
  return (
    a.member === b.member &&
    a.text === b.text &&
    a.replyTo === b.replyTo &&
    a.replyToCoach === b.replyToCoach &&
    a.mentionsCoach === b.mentionsCoach &&
    aMentions.length === bMentions.length &&
    aMentions.every((member, index) => member === bMentions[index])
  );
}
