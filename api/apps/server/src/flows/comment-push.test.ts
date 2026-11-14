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
  const character = Character.parse({
    nickname: '安安',
    look: { persona: 'deadpan', variants: { body: 'peach' }, colors: {} },
  });
  const profile = {
    catchphrase: null,
    character,
    jerseyNumber: null,
    joinedAt: new Date(0),
    equippedTitle: null,
    equippedTeamBadge: null,
  };
  const comment = { checkIn: other, comment: other, commenter: writer, text: '加油', author };

  it('answers once every push went out, and pushes a member already told no more', async () => {
    const sent: string[] = [];
    const told = new Set<string>();
    await Promise.all(
      [1, 2].map(() =>
        notifyComment(
          {
            members: {
              squadmates: () => Promise.resolve(new Map([[MemberId.parse(writer), profile]])),
            },
            push: {
              settingsOf: () =>
                Promise.resolve({ dailyProgress: true, coach: true, teammate: true }),
              notifyMembers: async ({ members }) => {
                await new Promise((resolve) => setTimeout(resolve, 10));
                sent.push(...members);
                return { sent: members.length, gone: 0, off: 0, failures: [] };
              },
            },
            // Written once a member, as the database's unique index keeps it.
            notices: {
              tell: (notices) => {
                const fresh = notices
                  .map(({ member }) => member)
                  .filter((member) => !told.has(member));
                for (const member of fresh) told.add(member);
                return Promise.resolve(fresh);
              },
            },
            log: createLog(() => undefined),
          },
          comment,
        ),
      ),
    );

    expect(sent).toStrictEqual([author]);
  });

  it('throws when it can’t read the commenter, so the event comes again', async () => {
    await expect(
      notifyComment(
        {
          members: { squadmates: () => Promise.reject(new Error('database down')) },
          push: { settingsOf: unused, notifyMembers: unused },
          notices: { tell: unused },
          log: createLog(() => undefined),
        },
        comment,
      ),
    ).rejects.toThrow('database down');
  });
});

const unused = () => Promise.reject(new Error('not used'));

describe('a coach’s line pushed', () => {
  it('reads as a teammate’s comment or reply, silently, and never reaches a member who turned the coach’s push off', async () => {
    const sent: { members: readonly string[]; notification: PushNotification }[] = [];
    const on = new Set([author]);
    const push = {
      // The coach's own switch: off for `writer`, whose daily push stays on.
      settingsOf: (member: string) =>
        Promise.resolve({ dailyProgress: true, coach: on.has(member), teammate: true }),
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
      news: 'comment',
      about: other,
    });
    await pushCoachLine(deps, {
      checkIn: other,
      member: author,
      coachName: '毛头',
      text: '那就再跑一圈',
      news: 'reply',
      about: writer,
    });
    await pushCoachLine(deps, {
      checkIn: other,
      member: writer,
      coachName: '毛头',
      text: '你也来',
      news: 'reply',
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
          interruption: 'passive',
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
          interruption: 'passive',
          event: { kind: 'comment', checkIn: other },
        },
      },
    ]);
  });

  it('@s a teammate as a teammate’s @ does', async () => {
    const sent: PushNotification[] = [];
    const deps = {
      push: {
        settingsOf: () => Promise.resolve({ dailyProgress: true, coach: true, teammate: true }),
        notifyMembers: (input: { notification: PushNotification }) => {
          sent.push(input.notification);
          return Promise.resolve({ sent: 1, gone: 0, off: 0, failures: [] });
        },
      },
      log: createLog(() => undefined),
    };
    await pushCoachLine(deps, {
      checkIn: other,
      member: writer,
      coachName: '毛头',
      text: '@小美 你也来',
      news: 'mention',
      about: other,
    });
    expect(sent.map(({ alert }) => alert)).toStrictEqual([
      { key: 'push.comment.mention', args: ['毛头', '@小美 你也来'] },
    ]);
  });
});
