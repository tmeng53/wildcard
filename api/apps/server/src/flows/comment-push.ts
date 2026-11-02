import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import { MemberId as PushMember, type Push, type PushNotification } from '@wildcard/push';

import { setTimeout as wait } from 'node:timers/promises';

import type { Log } from '../log.js';
import { pushAlert } from '../push-copy.js';

/** How long a comment's answer waits for its push; a slower one goes on, and the comment answers. */
const PUSH_WAIT_MS = 3000;

export interface CommentPushDependencies {
  readonly members: Pick<Members, 'squadmates'>;
  readonly push: Pick<Push, 'settingsOf' | 'notifyMembers'>;
  readonly log: Log;
}

/** A comment just written, and who it concerns. */
export interface NewComment {
  readonly checkIn: string;
  readonly comment: string;
  /** Who wrote it. */
  readonly commenter: string;
  readonly text: string;
  /** Who posted the check-in. */
  readonly author: string;
  /** Whom it replies to, when it does. */
  readonly replyTo?: string | undefined;
}

/**
 * Tells the check-in's author about a new comment on it, and the member it replies to about the
 * reply, never the commenter. Each gets one push per comment, unless they turned off push (the
 * app's one 通知 switch, `dailyProgress`). Never throws, and waits at most `PUSH_WAIT_MS`: a
 * comment is saved whether or not a phone hears of it.
 */
export async function notifyComment(
  deps: CommentPushDependencies,
  comment: NewComment,
): Promise<void> {
  const stop = new AbortController();
  const late = wait(PUSH_WAIT_MS, 'late' as const, { signal: stop.signal }).catch(() => undefined);
  const outcome = await Promise.race([send(deps, comment), late]);
  stop.abort();
  if (outcome === 'late') deps.log.warn('comment push still sending', { checkIn: comment.checkIn });
}

async function send(deps: CommentPushDependencies, comment: NewComment): Promise<void> {
  try {
    const told = recipients(comment);
    if (told.length === 0) return;
    const profiles = await deps.members.squadmates([ProfileMember.parse(comment.commenter)]);
    const nickname = profiles.get(ProfileMember.parse(comment.commenter))?.character?.nickname;
    // A member without a name yet is still mid-sign-up, and can't have commented; say nothing.
    if (nickname === undefined) return;
    await Promise.all(
      told.map(async ({ member, reply }) => {
        const to = PushMember.parse(member);
        if (!(await deps.push.settingsOf(to)).dailyProgress) return;
        const outcome = await deps.push.notifyMembers({
          members: [to],
          notification: commentNotification({ ...comment, nickname, reply }),
        });
        if (outcome.failures.length > 0) {
          deps.log.warn('comment push not sent to every phone', {
            member,
            failures: outcome.failures,
          });
        }
      }),
    );
  } catch (error) {
    deps.log.error('comment push not sent', { checkIn: comment.checkIn, error });
  }
}

/**
 * Who hears of the comment: the author (as a reply when it replies to them) and the member it
 * replies to, each once, never the commenter.
 */
export function recipients({
  commenter,
  author,
  replyTo,
}: Pick<NewComment, 'commenter' | 'author' | 'replyTo'>): {
  readonly member: string;
  readonly reply: boolean;
}[] {
  const told = new Map<string, boolean>();
  if (replyTo !== undefined) told.set(replyTo, true);
  if (!told.has(author)) told.set(author, false);
  told.delete(commenter);
  return [...told].map(([member, reply]) => ({ member, reply }));
}

/**
 * The push about a comment: a String Catalog key filled with the commenter's nickname and the
 * comment's own words, 「小美评论了你：加油」, or 「小美回复了你：加油」
 * for a reply to them. A tap opens the post's page.
 */
export function commentNotification({
  checkIn,
  comment,
  nickname,
  text,
  reply,
}: {
  readonly checkIn: string;
  readonly comment: string;
  readonly nickname: string;
  readonly text: string;
  readonly reply: boolean;
}): PushNotification {
  return {
    alert: pushAlert(reply ? 'push.comment.reply' : 'push.comment', [nickname, text]),
    category: 'comment',
    thread: `comments-${checkIn}`,
    collapseId: `comment-${comment}`,
    interruption: 'active',
    event: { kind: 'comment', checkIn, comment },
  };
}
