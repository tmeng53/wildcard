import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import { MemberId as NoticeMember, type Notices } from '@wildcard/notices';
import { MemberId as PushMember, type Push, type PushNotification } from '@wildcard/push';

import type { TrainedWithNamed } from '../events.js';
import type { Log } from '../log.js';
import { pushAlert } from '../push-copy.js';
import { noticeAlert } from './daily-progress-push.js';

export interface TrainedWithPushDependencies {
  readonly members: Pick<Members, 'squadmates'>;
  readonly push: Pick<Push, 'settingsOf' | 'notifyMembers'>;
  readonly notices: Pick<Notices, 'tell'>;
  readonly log: Log;
}

/**
 * Tells each squadmate a 训练 names it was done with (一起练), once a post: in their 通知, and by
 * one push unless they turned off push (the `dailyProgress` switch, which covers teammates'
 * pushes). A tap opens their own 训练 to post, filled from this one; the tag never counts for
 * them. It runs as the `trained-with-push` event's subscriber and waits for every push. The notice
 * is written once a member a post, before the push, and only those told now are pushed, so a post
 * delivered or edited twice pushes once; a push that fails after its notice is written is not
 * tried again, as with comments, and the notice in 通知 stands for it.
 */
export async function notifyTrainedWith(
  deps: TrainedWithPushDependencies,
  { checkIn, author, members }: Pick<TrainedWithNamed, 'checkIn' | 'author' | 'members'>,
): Promise<void> {
  const told = members.filter((member) => member !== author);
  if (told.length === 0) return;
  const profiles = await deps.members.squadmates([ProfileMember.parse(author)]);
  const nickname = profiles.get(ProfileMember.parse(author))?.character?.nickname;
  // A member without a name yet is still mid-sign-up, and can't have posted; say nothing.
  if (nickname === undefined) return;
  const notification = trainedWithNotification({ checkIn, nickname });
  const fresh = await tellNotices(deps, { checkIn, members: told, notification });
  await Promise.all(
    told
      .filter((member) => fresh.has(member))
      .map(async (member) => {
        const to = PushMember.parse(member);
        if (!(await deps.push.settingsOf(to)).dailyProgress) return;
        const outcome = await deps.push.notifyMembers({ members: [to], notification });
        if (outcome.failures.length > 0) {
          deps.log.warn('trained-with push not sent to every phone', {
            member,
            failures: outcome.failures,
          });
        }
      }),
  );
}

/**
 * Keeps the push in each member's 通知 before it is sent, and answers with the members to push:
 * those told now, so a post delivered or edited twice is pushed once. Never fails the push: when
 * the notices can't be written, everyone is pushed.
 */
async function tellNotices(
  deps: TrainedWithPushDependencies,
  {
    checkIn,
    members,
    notification,
  }: {
    readonly checkIn: string;
    readonly members: readonly string[];
    readonly notification: PushNotification;
  },
): Promise<ReadonlySet<string>> {
  try {
    const told = await deps.notices.tell(
      members.map((member) => ({
        member: NoticeMember.parse(member),
        kind: 'trainedWith',
        subject: { version: 1, alert: noticeAlert(notification), checkIn },
      })),
    );
    return new Set<string>(told);
  } catch (error) {
    deps.log.warn('trained-with push not kept in notices', { checkIn, error });
    return new Set(members);
  }
}

/**
 * The push to a squadmate a 训练 names: 「小美 @了你：你们一起练了，点开也发一条」. A tap
 * opens their own 训练, filled from this one.
 */
export function trainedWithNotification({
  checkIn,
  nickname,
}: {
  readonly checkIn: string;
  readonly nickname: string;
}): PushNotification {
  return {
    alert: pushAlert('push.trainedWith', [nickname]),
    category: 'trainedWith',
    thread: `trained-with-${checkIn}`,
    collapseId: `trained-with-${checkIn}`,
    interruption: 'active',
    event: { kind: 'trainedWith', checkIn },
  };
}
