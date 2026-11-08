import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import { MemberId as NoticeMember, type Notices } from '@wildcard/notices';
import { MemberId as PushMember, type Push, type PushNotification } from '@wildcard/push';

import type { Log } from '../log.js';
import { pushAlert } from '../push-copy.js';
import { noticeAlert } from './daily-progress-push.js';

export interface CommentPushDependencies {
  readonly members: Pick<Members, 'squadmates'>;
  readonly push: Pick<Push, 'settingsOf' | 'notifyMembers'>;
  readonly notices: Pick<Notices, 'tell'>;
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
  /** Whom it @s, in the order written. */
  readonly mentions?: readonly string[] | undefined;
}

/** Why a member hears of a comment: it is on their post, replies to them, or @s them. */
export type CommentNews = 'comment' | 'reply' | 'mention';

/**
 * Tells the check-in's author about a new comment on it, the member it replies to about the
 * reply and each member it @s about the @, never the commenter: in their 通知 (the bell), and by
 * one push per comment unless they turned off push (the app's one 通知 switch, `dailyProgress`),
 * which only stops the phone. It runs as the `comment-push` event's subscriber, after the comment
 * was saved, and waits for every push: a failure throws, so the event is delivered again, and a
 * member already told (the notice is written once a member) is not pushed again.
 */
export async function notifyComment(
  deps: CommentPushDependencies,
  comment: NewComment,
): Promise<void> {
  const told = recipients(comment);
  if (told.length === 0) return;
  const profiles = await deps.members.squadmates([ProfileMember.parse(comment.commenter)]);
  const nickname = profiles.get(ProfileMember.parse(comment.commenter))?.character?.nickname;
  // A member without a name yet is still mid-sign-up, and can't have commented; say nothing.
  if (nickname === undefined) return;
  const notifications = told.map(({ member, news }) => ({
    member,
    notification: commentNotification({ ...comment, nickname, news }),
  }));
  const fresh = await tellNotices(deps, { ...comment, notifications });
  await Promise.all(
    notifications
      .filter(({ member }) => fresh.has(member))
      .map(async ({ member, notification }) => {
        const to = PushMember.parse(member);
        if (!(await deps.push.settingsOf(to)).dailyProgress) return;
        const outcome = await deps.push.notifyMembers({ members: [to], notification });
        if (outcome.failures.length > 0) {
          deps.log.warn('comment push not sent to every phone', {
            member,
            failures: outcome.failures,
          });
        }
      }),
  );
}

/**
 * Keeps each push in its member's 通知 before it is sent, and answers with the members to push:
 * those told now, so a comment delivered twice is pushed once. Never fails the push: when the
 * notices can't be written, everyone is pushed.
 */
async function tellNotices(
  deps: CommentPushDependencies,
  {
    checkIn,
    comment,
    notifications,
  }: Pick<NewComment, 'checkIn' | 'comment'> & {
    readonly notifications: readonly {
      readonly member: string;
      readonly notification: PushNotification;
    }[];
  },
): Promise<ReadonlySet<string>> {
  try {
    const told = await deps.notices.tell(
      notifications.map(({ member, notification }) => ({
        member: NoticeMember.parse(member),
        kind: 'comment',
        subject: { version: 1, alert: noticeAlert(notification), checkIn, comment },
      })),
    );
    return new Set<string>(told);
  } catch (error) {
    deps.log.warn('comment push not kept in notices', { checkIn, error });
    return new Set(notifications.map(({ member }) => member));
  }
}

/**
 * Who hears of the comment, each once and never the commenter: the member it replies to, then
 * those it @s, then the author; each by the first reason that holds (a reply to the author
 * tells them of the reply).
 */
export function recipients({
  commenter,
  author,
  replyTo,
  mentions = [],
}: Pick<NewComment, 'commenter' | 'author' | 'replyTo' | 'mentions'>): {
  readonly member: string;
  readonly news: CommentNews;
}[] {
  const told = new Map<string, CommentNews>();
  if (replyTo !== undefined) told.set(replyTo, 'reply');
  for (const member of mentions) if (!told.has(member)) told.set(member, 'mention');
  if (!told.has(author)) told.set(author, 'comment');
  told.delete(commenter);
  return [...told].map(([member, news]) => ({ member, news }));
}

const NEWS_KEY = {
  comment: 'push.comment',
  reply: 'push.comment.reply',
  mention: 'push.comment.mention',
} as const;

/**
 * The push about a comment: a String Catalog key filled with the commenter's nickname and the
 * comment's own words, 「小美评论了你：加油」, 「小美回复了你：加油」 for a reply to them or
 * 「小美@了你：加油」 for an @ of them. A tap opens the post's page.
 */
export function commentNotification({
  checkIn,
  comment,
  nickname,
  text,
  news,
}: {
  readonly checkIn: string;
  readonly comment: string;
  readonly nickname: string;
  readonly text: string;
  readonly news: CommentNews;
}): PushNotification {
  return {
    alert: pushAlert(NEWS_KEY[news], [nickname, text]),
    category: 'comment',
    thread: `comments-${checkIn}`,
    collapseId: `comment-${comment}`,
    interruption: 'active',
    event: { kind: 'comment', checkIn, comment },
  };
}

/** A line the coach just said to a member: a reply to their check-in, or an answer to them. */
export interface CoachLine {
  readonly checkIn: string;
  /** Whom it is to. */
  readonly member: string;
  /** The coach's name now. */
  readonly coachName: string;
  readonly text: string;
  /**
   * What it is to them: a reply to their check-in, an answer to their reply to the coach, or an
   * @ of them under anyone's check-in.
   */
  readonly news: CommentNews;
  /** Names the push, so a retry shows once: the reply it answers, or the check-in. */
  readonly about: string;
}

/** The alert of a coach's line: the same words as a teammate's comment, with the coach's name. */
export function coachLineAlert(line: Pick<CoachLine, 'coachName' | 'text' | 'news'>) {
  return pushAlert(NEWS_KEY[line.news], [line.coachName, line.text]);
}

/**
 * Pushes a coach's line to the member it is to, as a teammate's comment or reply is pushed
 * (「毛头评论了你：…」, 「毛头回复了你：…」), unless they turned off push. Its 通知 is the coach
 * notice the caller keeps. Never throws.
 */
export async function pushCoachLine(
  deps: Pick<CommentPushDependencies, 'push' | 'log'>,
  line: CoachLine,
): Promise<void> {
  try {
    const to = PushMember.parse(line.member);
    // The coach's own switch; its words are in the member's bell whatever it is.
    if (!(await deps.push.settingsOf(to)).coach) return;
    const notification: PushNotification = {
      alert: coachLineAlert(line),
      category: 'comment',
      thread: `comments-${line.checkIn}`,
      collapseId: `coach-${line.about}`,
      // Silent: the coach talks a lot, so it never rings or lights up the phone.
      interruption: 'passive',
      event: { kind: 'comment', checkIn: line.checkIn },
    };
    const outcome = await deps.push.notifyMembers({ members: [to], notification });
    if (outcome.failures.length > 0) {
      deps.log.warn('coach push not sent to every phone', {
        member: line.member,
        failures: outcome.failures,
      });
    }
  } catch (error) {
    deps.log.error('coach push not sent', { checkIn: line.checkIn, error });
  }
}
