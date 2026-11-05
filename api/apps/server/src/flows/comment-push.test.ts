import { Character, MemberId } from '@wildcard/members';
import type { PushNotification } from '@wildcard/push';
import { describe, expect, it } from 'vitest';

import { createLog } from '../log.js';
import { notifyComment, pushCoachLine, recipients } from './comment-push.js';

const [writer, author, other] = [
  '00000000-0000-4000-8000-00000000000a',
  '00000000-0000-4000-8000-00000000000b',
  '00000000-0000-4000-8000-00000000000c',
];

describe('who hears of a comment', () => {
  it('is the author, and the member it replies to as a reply, never the writer', () => {
    expect(recipients({ commenter: writer, author })).toStrictEqual([
      { member: author, news: 'comment' },
    ]);
    expect(recipients({ commenter: writer, author, replyTo: other })).toStrictEqual([
      { member: other, news: 'reply' },
      { member: author, news: 'comment' },
    ]);
    expect(recipients({ commenter: writer, author, replyTo: author })).toStrictEqual([
      { member: author, news: 'reply' },
    ]);
    expect(recipients({ commenter: author, author, replyTo: other })).toStrictEqual([
      { member: other, news: 'reply' },
    ]);
    expect(recipients({ commenter: author, author })).toStrictEqual([]);
  });

  it('tells each member it @s of the @, once, unless it replies to them', () => {
    const fourth = '00000000-0000-4000-8000-00000000000d';
    expect(
      recipients({ commenter: writer, author, mentions: [other, author, fourth, writer] }),
    ).toStrictEqual([
      { member: other, news: 'mention' },
      { member: author, news: 'mention' },
      { member: fourth, news: 'mention' },
    ]);
    expect(
      recipients({ commenter: writer, author, replyTo: other, mentions: [other, fourth] }),
    ).toStrictEqual([
      { member: other, news: 'reply' },
      { member: fourth, news: 'mention' },
      { member: author, news: 'comment' },
    ]);
  });
});

describe('a comment push', () => {
  it('stops holding the comment’s answer once APNs is slow, and says so', async () => {
    const lines: string[] = [];
    const character = Character.parse({
      nickname: '安安',
      look: { persona: 'deadpan', variants: { body: 'peach' }, colors: {} },
    });
    const members = {
      squadmates: () =>
        Promise.resolve(
          new Map([
            [
              MemberId.parse(writer),
              {
                catchphrase: null,
                character,
                jerseyNumber: null,
                joinedAt: new Date(0),
                equippedTitle: null,
              },
            ],
          ]),
        ),
    };
    const push = {
      settingsOf: () => Promise.resolve({ dailyProgress: true }),
      // Never answers, as a hung connection wouldn't.
      notifyMembers: () => new Promise<never>(() => undefined),
    };
    const started = Date.now();

    await notifyComment(
      {
        members,
        push,
        notices: { tell: () => Promise.resolve() },
        log: createLog((line) => lines.push(line)),
      },
      { checkIn: other, comment: other, commenter: writer, text: '加油', author },
    );

    expect(Date.now() - started).toBeLessThan(4000);
    expect(lines.some((line) => line.includes('comment push still sending'))).toBe(true);
  });
});

describe('a coach’s line pushed', () => {
  it('reads as a teammate’s comment or reply, and never reaches a member who turned push off', async () => {
    const sent: { members: readonly string[]; notification: PushNotification }[] = [];
    const on = new Set([author]);
    const push = {
      settingsOf: (member: string) => Promise.resolve({ dailyProgress: on.has(member) }),
      notifyMembers: (input: { members: readonly string[]; notification: PushNotification }) => {
        sent.push(input);
        return Promise.resolve({ sent: 1, gone: 0, off: 0, failures: [] });
      },
    };
    const deps = { push, log: createLog(() => undefined) };
    await pushCoachLine(deps, {
      checkIn: other,
      member: author,
      coachName: '毛头',
      text: '腿还在吗',
      answer: false,
      about: other,
    });
    await pushCoachLine(deps, {
      checkIn: other,
      member: author,
      coachName: '毛头',
      text: '那就再跑一圈',
      answer: true,
      about: writer,
    });
    await pushCoachLine(deps, {
      checkIn: other,
      member: writer,
      coachName: '毛头',
      text: '你也来',
      answer: true,
      about: writer,
    });
    expect(sent).toStrictEqual([
      {
        members: [author],
        notification: {
          alert: { key: 'push.comment', args: ['毛头', '腿还在吗'] },
          category: 'comment',
          thread: `comments-${other}`,
          collapseId: `coach-${other}`,
          interruption: 'active',
          event: { kind: 'comment', checkIn: other },
        },
      },
      {
        members: [author],
        notification: {
          alert: { key: 'push.comment.reply', args: ['毛头', '那就再跑一圈'] },
          category: 'comment',
          thread: `comments-${other}`,
          collapseId: `coach-${writer}`,
          interruption: 'active',
          event: { kind: 'comment', checkIn: other },
        },
      },
    ]);
  });
});
