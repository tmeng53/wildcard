import type { CheckInId, MemberId } from '../../domain/check-in.js';
import type { Comment, CommentId } from '../../domain/comment.js';
import type { CommentText } from '../../domain/text.js';
import {
  CommentIdConflictError,
  NotYourCommentError,
  ReplyToCoachNotFoundError,
  ReplyToNotInSquadError,
} from '../../errors.js';
import type {
  CheckInStore,
  Clock,
  CoachSpoke,
  CommentStore,
  SquadMembership,
} from '../../ports.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';

interface Deps {
  readonly store: CheckInStore;
  readonly membership: SquadMembership;
  readonly comments: CommentStore;
  /** Whether a coach spoke under a check-in; without it, no comment may reply to a coach. */
  readonly coachSpoke?: CoachSpoke | undefined;
}

export interface CommentInput {
  readonly checkIn: CheckInId;
  readonly id: CommentId;
  readonly member: MemberId;
  readonly text: CommentText;
  readonly replyTo?: MemberId | undefined;
  /** The coach it replies to, by id. Never with `replyTo`. */
  readonly replyToCoach?: string | undefined;
}

export interface Commented {
  readonly comment: Comment;
  readonly created: boolean;
  /** Who posted the check-in, to tell them about a new comment. */
  readonly author: MemberId;
}

/**
 * Writes the member's comment under a check-in they can see, their own included. The same
 * comment under the same id again changes nothing, so a retry is safe. A reply names someone who
 * can see the check-in: its author, or a member of a squad the commenter sees it through; or the
 * coach of such a squad that said something under it. Throws `CheckInNotFoundError` for a
 * check-in they can't see, `ReplyToNotInSquadError` for a reply to anyone else,
 * `ReplyToCoachNotFoundError` for one to any other coach and `CommentIdConflictError` for an id
 * that holds another comment.
 */
export async function commentOnCheckIn(
  deps: Deps & { readonly clock: Clock },
  { checkIn: id, id: commentId, member, text, replyTo, replyToCoach }: CommentInput,
): Promise<Commented> {
  const { checkIn, through } = await findVisibleCheckIn(deps, { id, viewer: member });
  if (replyTo !== undefined && replyTo !== checkIn.member) {
    const teammates = await deps.membership.membersOfAny(through);
    if (!teammates.has(replyTo)) throw new ReplyToNotInSquadError();
  }
  if (replyToCoach !== undefined) {
    const spoke =
      replyTo === undefined &&
      ((await deps.coachSpoke?.({ checkIn: id, squads: through, coach: replyToCoach })) ?? false);
    if (!spoke) throw new ReplyToCoachNotFoundError();
  }
  const asked: Comment = {
    id: commentId,
    member,
    text,
    ...(replyTo === undefined ? {} : { replyTo }),
    ...(replyToCoach === undefined ? {} : { replyToCoach }),
    commentedAt: deps.clock(),
  };
  const outcome = await deps.comments.insert(id, asked);
  if (outcome === 'conflict') throw new CommentIdConflictError(commentId);
  if (outcome === 'created') return { comment: asked, created: true, author: checkIn.member };
  // Saved before: answer with it as it was first written.
  const saved = await deps.comments.find(commentId);
  return { comment: saved ?? asked, created: false, author: checkIn.member };
}

/**
 * Deletes the member's own comment, even under a check-in they no longer see (they left the
 * squad): their words stay theirs. Safe to repeat: a comment that is gone deletes nothing, and
 * one that was never on this check-in deletes nothing either. Throws `CheckInNotFoundError` for a
 * check-in they can't see (unless the comment on it is theirs) and `NotYourCommentError` for
 * someone else's comment.
 */
export async function deleteComment(
  deps: Deps,
  {
    checkIn,
    id,
    member,
  }: { readonly checkIn: CheckInId; readonly id: CommentId; readonly member: MemberId },
): Promise<void> {
  const saved = await deps.comments.find(id);
  // Gone already (a retry, even after leaving): ids are random, so this tells nobody anything.
  if (saved === undefined) return;
  if (saved.checkIn === checkIn && saved.member === member) {
    await deps.comments.remove(id);
    return;
  }
  await findVisibleCheckIn(deps, { id: checkIn, viewer: member });
  if (saved.checkIn !== checkIn) return;
  throw new NotYourCommentError();
}
