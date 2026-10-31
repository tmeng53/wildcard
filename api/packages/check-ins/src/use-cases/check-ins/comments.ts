import type { CheckInId, MemberId } from '../../domain/check-in.js';
import type { Comment, CommentId } from '../../domain/comment.js';
import type { CommentText } from '../../domain/text.js';
import {
  CommentIdConflictError,
  NotYourCommentError,
  ReplyToNotInSquadError,
} from '../../errors.js';
import type { CheckInStore, Clock, CommentStore, SquadMembership } from '../../ports.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';

interface Deps {
  readonly store: CheckInStore;
  readonly membership: SquadMembership;
  readonly comments: CommentStore;
}

export interface CommentInput {
  readonly checkIn: CheckInId;
  readonly id: CommentId;
  readonly member: MemberId;
  readonly text: CommentText;
  readonly replyTo?: MemberId | undefined;
}

export interface Commented {
  readonly comment: Comment;
  readonly created: boolean;
}

/**
 * Writes the member's comment under a check-in they can see, their own included. The same
 * comment under the same id again changes nothing, so a retry is safe. A reply names someone who
 * can see the check-in: its author, or a member of a squad the commenter sees it through. Throws
 * `CheckInNotFoundError` for a check-in they can't see, `ReplyToNotInSquadError` for a reply to
 * anyone else and `CommentIdConflictError` for an id that holds another comment.
 */
export async function commentOnCheckIn(
  deps: Deps & { readonly clock: Clock },
  { checkIn: id, id: commentId, member, text, replyTo }: CommentInput,
): Promise<Commented> {
  const { checkIn, through } = await findVisibleCheckIn(deps, { id, viewer: member });
  if (replyTo !== undefined && replyTo !== checkIn.member) {
    const teammates = await deps.membership.membersOfAny(through);
    if (!teammates.has(replyTo)) throw new ReplyToNotInSquadError();
  }
  const asked: Comment = {
    id: commentId,
    member,
    text,
    ...(replyTo === undefined ? {} : { replyTo }),
    commentedAt: deps.clock(),
  };
  const outcome = await deps.comments.insert(id, asked);
  if (outcome === 'conflict') throw new CommentIdConflictError(commentId);
  if (outcome === 'created') return { comment: asked, created: true };
  // Saved before: answer with it as it was first written.
  const saved = await deps.comments.find(commentId);
  return { comment: saved ?? asked, created: false };
}

/**
 * Deletes the member's own comment. Safe to repeat: a comment that is gone, or was never on this
 * check-in, deletes nothing. Throws `CheckInNotFoundError` for a check-in they can't see and
 * `NotYourCommentError` for someone else's comment.
 */
export async function deleteComment(
  deps: Deps,
  {
    checkIn,
    id,
    member,
  }: { readonly checkIn: CheckInId; readonly id: CommentId; readonly member: MemberId },
): Promise<void> {
  await findVisibleCheckIn(deps, { id: checkIn, viewer: member });
  const saved = await deps.comments.find(id);
  if (saved?.checkIn !== checkIn) return;
  if (saved.member !== member) throw new NotYourCommentError();
  await deps.comments.remove(id);
}
