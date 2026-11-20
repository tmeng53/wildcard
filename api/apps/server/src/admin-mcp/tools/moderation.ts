import { CheckInId, CommentId, MemberId, type CheckIns } from '@wildcard/check-ins';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// What members report (举报, App Review guideline 1.2) is filed as an issue in the private
// feedback repository; this is how an admin takes down what breaks the terms.

interface ModerationToolDependencies {
  /**
   * The app's own check-ins, not the call's transaction: deleting a post also deletes its
   * photos in Storage, which no transaction covers, as when its author deletes it.
   */
  readonly checkIns: Pick<CheckIns, 'current' | 'post' | 'delete' | 'deleteComment'>;
}

/** `remove_content`: deletes a reported post (with its photos, reactions and comments) or comment. */
export function removeContent({ checkIns }: ModerationToolDependencies) {
  return adminTool({
    name: 'remove_content',
    title: 'Remove a reported post or comment',
    description:
      'Deletes a post that breaks the terms, with its photos, reactions and comments, or one ' +
      'comment under it (`comment`), as if its author deleted it. Use it on what a content ' +
      'report (the `content-report` issues) names, after looking at it. Can’t be undone.',
    changes: true,
    input: z.strictObject({
      checkIn: CheckInId,
      comment: CommentId.optional().meta({
        description: 'The comment to remove; the whole post when left out.',
      }),
    }),
    run: async ({ checkIn, comment }) => {
      const record = await checkIns.current(checkIn);
      if (record === undefined) return { version: 1, removed: false, reason: 'no such post' };
      if (comment === undefined) {
        await checkIns.delete({ id: checkIn, member: record.member });
        return { version: 1, removed: true, checkIn };
      }
      const { comments } = await checkIns.post({ id: checkIn, viewer: record.member });
      const found = comments.find((each) => each.id === comment);
      if (found === undefined) return { version: 1, removed: false, reason: 'no such comment' };
      await checkIns.deleteComment({
        checkIn,
        id: comment,
        member: MemberId.parse(found.member),
      });
      return { version: 1, removed: true, checkIn, comment };
    },
  });
}

export const moderationTools = (deps: ModerationToolDependencies) => [removeContent(deps)];
