import { Character, MemberId } from '@wildcard/members';
import { describe, expect, it } from 'vitest';

import { createLog } from '../log.js';
import { notifyComment, recipients } from './comment-push.js';

const [writer, author, other] = [
  '00000000-0000-4000-8000-00000000000a',
  '00000000-0000-4000-8000-00000000000b',
  '00000000-0000-4000-8000-00000000000c',
];

describe('who hears of a comment', () => {
  it('is the author, and the member it replies to as a reply, never the writer', () => {
    expect(recipients({ commenter: writer, author })).toStrictEqual([
      { member: author, reply: false },
    ]);
    expect(recipients({ commenter: writer, author, replyTo: other })).toStrictEqual([
      { member: other, reply: true },
      { member: author, reply: false },
    ]);
    expect(recipients({ commenter: writer, author, replyTo: author })).toStrictEqual([
      { member: author, reply: true },
    ]);
    expect(recipients({ commenter: author, author, replyTo: other })).toStrictEqual([
      { member: other, reply: true },
    ]);
    expect(recipients({ commenter: author, author })).toStrictEqual([]);
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
        Promise.resolve(new Map([[MemberId.parse(writer), { catchphrase: null, character }]])),
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
