import { Character, MemberId } from '@wildcard/members';
import type { NewNotice } from '@wildcard/notices';
import type { PushNotification } from '@wildcard/push';
import { describe, expect, it } from 'vitest';

import { createLog } from '../log.js';
import { notifyTrainedWith } from './trained-with-push.js';

const [author, mia, coco, post] = [
  '00000000-0000-4000-8000-00000000000a',
  '00000000-0000-4000-8000-00000000000b',
  '00000000-0000-4000-8000-00000000000c',
  '00000000-0000-4000-8000-00000000000d',
];

const profile = {
  catchphrase: null,
  character: Character.parse({
    nickname: '阿杰',
    look: { persona: 'deadpan', variants: { body: 'peach' }, colors: {} },
  }),
  jerseyNumber: null,
  joinedAt: new Date(0),
  equippedTitle: null,
  equippedTeamBadge: null,
};

/** The flow with fakes: notices written once a member a post, as the unique index keeps them. */
function flow({ pushOff = new Set<string>() } = {}) {
  const pushed: { readonly member: string; readonly notification: PushNotification }[] = [];
  const kept: NewNotice[] = [];
  const told = new Set<string>();
  const deps = {
    members: { squadmates: () => Promise.resolve(new Map([[MemberId.parse(author), profile]])) },
    push: {
      settingsOf: (member: string) =>
        Promise.resolve({ dailyProgress: !pushOff.has(member), coach: true, teammate: true }),
      notifyMembers: ({
        members,
        notification,
      }: {
        readonly members: readonly string[];
        readonly notification: PushNotification;
      }) => {
        pushed.push(...members.map((member) => ({ member, notification })));
        return Promise.resolve({ sent: members.length, gone: 0, off: 0, failures: [] });
      },
    },
    notices: {
      tell: (notices: readonly NewNotice[]) => {
        kept.push(...notices);
        const fresh = notices.map(({ member }) => member).filter((member) => !told.has(member));
        for (const member of fresh) told.add(member);
        return Promise.resolve(fresh);
      },
    },
    log: createLog(() => undefined),
  };
  return { deps, pushed, kept };
}

describe('telling the squadmates a 训练 names', () => {
  it('pushes each once with the author’s name, and keeps it in their 通知', async () => {
    const { deps, pushed, kept } = flow();
    await notifyTrainedWith(deps, { checkIn: post, author, members: [mia, coco] });
    expect(pushed.map(({ member }) => member)).toStrictEqual([mia, coco]);
    expect(pushed[0]?.notification).toStrictEqual({
      alert: { key: 'push.trainedWith', args: ['阿杰'] },
      category: 'trainedWith',
      thread: `trained-with-${post}`,
      collapseId: `trained-with-${post}`,
      interruption: 'active',
      event: { kind: 'trainedWith', checkIn: post },
      // A build from before the 一起练 push has no words for it.
      since: 3,
    });
    expect(kept.map(({ member, kind, subject }) => [member, kind, subject])).toStrictEqual([
      [
        mia,
        'trainedWith',
        { version: 1, alert: { key: 'push.trainedWith', args: ['阿杰'] }, checkIn: post },
      ],
      [
        coco,
        'trainedWith',
        { version: 1, alert: { key: 'push.trainedWith', args: ['阿杰'] }, checkIn: post },
      ],
    ]);
  });

  it('pushes only those new to the post when an edit names someone more', async () => {
    const { deps, pushed } = flow();
    await notifyTrainedWith(deps, { checkIn: post, author, members: [mia] });
    await notifyTrainedWith(deps, { checkIn: post, author, members: [mia, coco] });
    expect(pushed.map(({ member }) => member)).toStrictEqual([mia, coco]);
  });

  it('keeps the notice but doesn’t push a member who turned push off, nor names the author', async () => {
    const { deps, pushed, kept } = flow({ pushOff: new Set([coco]) });
    await notifyTrainedWith(deps, { checkIn: post, author, members: [author, coco, mia] });
    expect(pushed.map(({ member }) => member)).toStrictEqual([mia]);
    expect(kept.map(({ member }) => member)).toStrictEqual([coco, mia]);
  });
});
