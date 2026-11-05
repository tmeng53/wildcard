import type { NoteToDeliver } from '@wildcard/coach';
import { MemberId as ProfileMember } from '@wildcard/members';
import type { NewNotice } from '@wildcard/notices';
import type { PushNotification } from '@wildcard/push';
import { describe, expect, it } from 'vitest';

import { createLog } from '../log.js';
import { deliverCoachNotes } from './coach-notes.js';

const squad = '6f1c2a5e-8d3b-4f7a-9c2e-1b4d5a6e7f80';
const east = '00000000-0000-4000-8000-00000000000a';
const west = '00000000-0000-4000-8000-00000000000b';
const quiet = '00000000-0000-4000-8000-00000000000c';
const now = new Date('2026-11-05T11:05:00Z');

function note(id: number, member: string, text: string): NoteToDeliver {
  return {
    id,
    squad: squad as NoteToDeliver['squad'],
    member,
    coach: 'xiaohun' as NoteToDeliver['coach'],
    day: '2026-11-05',
    text,
    at: new Date('2026-11-05T11:00:00Z'),
    coachName: '毛头',
  };
}

function setUp(waiting: readonly NoteToDeliver[]) {
  const claimed = new Set<number>();
  const told: NewNotice[] = [];
  const sent: { members: readonly string[]; notification: PushNotification }[] = [];
  const hours: number[] = [];
  const deps = {
    notes: {
      waiting: () => Promise.resolve(waiting.filter(({ id }) => !claimed.has(id))),
      delivered: (id: number) => {
        if (claimed.has(id)) return Promise.resolve(false);
        claimed.add(id);
        return Promise.resolve(true);
      },
    },
    noteHour: () => Promise.resolve(8),
    // `east` and `quiet` are past 8am on their own clocks; `west` isn't yet.
    members: {
      pastLocalHour: ({ hour }: { readonly hour: number }) => {
        hours.push(hour);
        return Promise.resolve(
          [east, quiet].map((member) => ({
            member: ProfileMember.parse(member),
            day: '2026-11-05',
            hourTheDayBefore: new Date('2026-11-04T13:00:00Z'),
          })),
        );
      },
    },
    // `quiet` turned the coach's push off.
    push: {
      settingsOf: (member: string) =>
        Promise.resolve({ dailyProgress: true, coach: member !== quiet }),
      notifyMembers: (input: { members: readonly string[]; notification: PushNotification }) => {
        sent.push(input);
        return Promise.resolve({ sent: 1, gone: 0, off: 0, failures: [] });
      },
    },
    tell: (notices: readonly NewNotice[]) => {
      told.push(...notices);
      return Promise.resolve();
    },
    log: createLog(() => undefined),
    clock: () => now,
  };
  return { deps, told, sent, hours };
}

describe('the coach’s morning notes delivered', () => {
  it('reach each member past the hour once: in the bell always, by a silent push under the coach’s switch', async () => {
    const { deps, told, sent, hours } = setUp([
      note(1, east, '昨天那组深蹲我看见了'),
      note(2, west, '今天别硬撑'),
      note(3, quiet, '慢慢来'),
    ]);

    expect(await deliverCoachNotes(deps)).toStrictEqual({ waiting: 3, delivered: 2, pushed: 1 });
    // A second run finds only the note still waiting for its member's morning.
    expect(await deliverCoachNotes(deps)).toStrictEqual({ waiting: 1, delivered: 0, pushed: 0 });

    expect(hours).toStrictEqual([8, 8]);
    expect(told).toStrictEqual([
      {
        member: east,
        squad,
        kind: 'coachNote',
        subject: {
          version: 1,
          note: 1,
          coach: 'xiaohun',
          day: '2026-11-05',
          text: '昨天那组深蹲我看见了',
        },
      },
      {
        member: quiet,
        squad,
        kind: 'coachNote',
        subject: { version: 1, note: 3, coach: 'xiaohun', day: '2026-11-05', text: '慢慢来' },
      },
    ]);
    expect(sent).toStrictEqual([
      {
        members: [east],
        notification: {
          alert: { key: 'push.coach.note', args: ['毛头', '昨天那组深蹲我看见了'] },
          category: 'coachNote',
          thread: 'coach-notes',
          collapseId: 'coach-note-1',
          interruption: 'passive',
          event: { kind: 'coachNote', note: 1 },
        },
      },
    ]);
  });

  it('tells a note another run already claimed no more', async () => {
    const { deps, told, sent } = setUp([note(1, east, '早')]);
    await deps.notes.delivered(1);
    const waiting = [note(1, east, '早')];
    const run = await deliverCoachNotes({
      ...deps,
      notes: { ...deps.notes, waiting: () => Promise.resolve(waiting) },
    });
    expect(run).toStrictEqual({ waiting: 1, delivered: 0, pushed: 0 });
    expect(told).toStrictEqual([]);
    expect(sent).toStrictEqual([]);
  });
});
