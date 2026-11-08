import { MemberId, NoticeId, SquadId } from '@wildcard/notices';
import { describe, expect, it } from 'vitest';

import { NoticeEntry, noticeEntries } from './notices.js';

describe('a coachLetter notice', () => {
  it('carries the letter as written, with both coaches by their names now', async () => {
    const entries = await noticeEntries(
      {
        members: { squadmates: () => Promise.reject(new Error('No squadmates to read.')) },
        coachNames: () => {
          const names = new Map([
            ['xiaohun', '毛头'],
            ['papa', '帕帕'],
          ]);
          return Promise.resolve((coach: string) => names.get(coach));
        },
      },
      {
        notices: [
          {
            id: NoticeId.parse(7),
            member: MemberId.parse('11111111-1111-4111-8111-111111111111'),
            squad: SquadId.parse('33333333-3333-4333-8333-333333333333'),
            kind: 'coachLetter',
            subject: {
              version: 1,
              letter: 3,
              from: 'xiaohun',
              to: 'papa',
              day: '2026-11-08',
              text: '这队交给你了。',
            },
            at: new Date('2026-11-08T06:00:00Z'),
          },
        ],
        broadcasts: new Map(),
      },
    );
    expect(entries.map((entry) => NoticeEntry.parse(entry))).toStrictEqual([
      {
        id: 7,
        kind: 'coachLetter',
        at: '2026-11-08T06:00:00.000Z',
        squadId: '33333333-3333-4333-8333-333333333333',
        letter: 3,
        coach: 'xiaohun',
        coachName: '毛头',
        toCoach: 'papa',
        toCoachName: '帕帕',
        day: '2026-11-08',
        text: '这队交给你了。',
      },
    ]);
  });
});
