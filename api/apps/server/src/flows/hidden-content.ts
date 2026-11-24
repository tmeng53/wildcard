import { coachReplyKey, type Hidden } from '@wildcard/moderation';

/** A post as the feed, a post's page and 历史动态 serve it. */
interface Post {
  readonly checkIn: { readonly id: string; readonly member: string };
  readonly reactions: readonly { readonly member: string }[];
  readonly comments: readonly {
    readonly id: string;
    readonly member: string;
    readonly replyTo?: string | undefined;
  }[];
}

/** Whether `viewer` no longer sees a post: its author is blocked either way, or they reported it. */
export function isHiddenPost(hidden: Hidden, post: Post): boolean {
  return hidden.members.has(post.checkIn.member) || hidden.checkIns.has(post.checkIn.id);
}

/**
 * A post as the viewer sees it with blocks and reports applied: the reactions and comments of
 * members blocked either way, and comments they reported, left out. A reply to a comment left
 * out stays; it just names who it replied to.
 */
export function withoutHidden<P extends Post>(hidden: Hidden, post: P): P {
  return {
    ...post,
    reactions: post.reactions.filter((reaction) => !hidden.members.has(reaction.member)),
    comments: post.comments.filter(
      (comment) => !hidden.members.has(comment.member) && !hidden.comments.has(comment.id),
    ),
  };
}

/** The posts the viewer still sees, each with blocks and reports applied. */
export function visiblePosts<P extends Post>(hidden: Hidden, posts: readonly P[]): P[] {
  return posts
    .filter((post) => !isHiddenPost(hidden, post))
    .map((post) => withoutHidden(hidden, post));
}

/** Coach lines the viewer reported, left out. */
export function visibleCoachLines<
  R extends { readonly checkIn: string; readonly coach: { readonly id: string } },
  A extends { readonly comment: string },
>(hidden: Hidden, lines: { readonly replies: readonly R[]; readonly answers: readonly A[] }) {
  return {
    replies: lines.replies.filter(
      (reply) => !hidden.coachReplies.has(coachReplyKey(reply.checkIn, reply.coach.id)),
    ),
    answers: lines.answers.filter(
      (answer) => !hidden.coachAnswers.has(answer.comment) && !hidden.comments.has(answer.comment),
    ),
  };
}
