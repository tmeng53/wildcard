import { SquadId as CoachSquadId, type CoachWakes } from '@wildcard/coach';

import type { EventHandlers } from '../events.js';
import { notifyComment, type CommentPushDependencies } from './comment-push.js';

/**
 * What the server does after each event (`events.ts`): the squads' coaches look at a new
 * check-in, a new comment is told to whom it concerns, the coach it replies to or @s answers
 * it, and a squad's coach welcomes whoever joins it. Without a coach (no OpenAI key), the coach's part does nothing.
 */
export function eventHandlers(deps: {
  readonly coach: CoachWakes | undefined;
  readonly commentPush: CommentPushDependencies;
}): EventHandlers {
  return {
    'coach-look': async ({ checkIn, squads }) => {
      await deps.coach?.checkedIn({
        checkIn,
        squads: squads.map((squad) => CoachSquadId.parse(squad)),
      });
    },
    'comment-push': (comment) => notifyComment(deps.commentPush, comment),
    'coach-answer': async ({ checkIn, comment, coach, squads }) => {
      if (coach === undefined) return;
      await deps.coach?.answer({ checkIn, comment, coach, squads });
    },
    'coach-welcome': async ({ squad, member }) => {
      await deps.coach?.welcome({ squad: CoachSquadId.parse(squad), member });
    },
  };
}
