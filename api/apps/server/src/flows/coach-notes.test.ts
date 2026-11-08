import { CoachId, type NoteToDeliver, SquadId } from '@wildcard/coach';
import { MemberId as ProfileMember } from '@wildcard/members';
import type { NewNotice } from '@wildcard/notices';
import type { PushNotification } from '@wildcard/push';
import { MemberId as SquadMember } from '@wildcard/squads';
import { describe, expect, it } from 'vitest';

import { createLog } from '../log.js';
import { deliverCoachNotes } from './coach-notes.js';

const squad = '6f1c2a5e-8d3b-4f7a-9c2e-1b4d5a6e7f80';
const east = '00000000-0000-4000-8000-00000000000a';
const west = '00000000-0000-4000-8000-00000000000b';
const quiet = '00000000-0000-4000-8000-00000000000c';
const now = new Date('2026-11-05T11:05:00Z');

function note({ id, member, text }: { id: number; member: string; text: string }): NoteToDeliver {
  return {
    id,
    squad: SquadId.parse(squad),
    member,
    coach: CoachId.parse('xiaohun'),
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
    // Everyone is still in the squad, until a test says otherwise.
    squads: {
      membersOf: () =>
        Promise.resolve([east, west, quiet].map((member) => SquadMember.parse(member))),
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
    // The catalog's name, when the squad's language has none of its own.
    coachNames: () => Promise.resolve(() => undefined),
    log: createLog(() => undefined),
    clock: () => now,
  };
  return { deps, told, sent, hours };
}

describe('the coach’s morning notes delivered', () => {
  it('reach each member past the hour once, in the bell and by a silent push, and never a member who switched the coach off', async () => {
    const { deps, told, sent, hours } = setUp([
      note({ id: 1, member: east, text: '昨天那组深蹲我看见了' }),
      note({ id: 2, member: west, text: '今天别硬撑' }),
      note({ id: 3, member: quiet, text: '慢慢来' }),
    ]);

    expect(await deliverCoachNotes(deps)).toStrictEqual({ waiting: 3, delivered: 1, pushed: 1 });
    // A second run finds the note still waiting for its member's morning, and the one never told.
    expect(await deliverCoachNotes(deps)).toStrictEqual({ waiting: 2, delivered: 0, pushed: 0 });

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

  it('leaves out a member who has left the squad since the note was written', async () => {
    const { deps, told, sent } = setUp([note({ id: 1, member: east, text: '早' })]);
    const run = await deliverCoachNotes({
      ...deps,
      squads: { membersOf: () => Promise.resolve([SquadMember.parse(quiet)]) },
    });
    expect(run).toStrictEqual({ waiting: 1, delivered: 0, pushed: 0 });
    expect(told).toStrictEqual([]);
    expect(sent).toStrictEqual([]);
  });

  it('tells a note another run already claimed no more', async () => {
    const { deps, told, sent } = setUp([note({ id: 1, member: east, text: '早' })]);
    await deps.notes.delivered(1);
    const waiting = [note({ id: 1, member: east, text: '早' })];
    const run = await deliverCoachNotes({
      ...deps,
      notes: { ...deps.notes, waiting: () => Promise.resolve(waiting) },
    });
    expect(run).toStrictEqual({ waiting: 1, delivered: 0, pushed: 0 });
    expect(told).toStrictEqual([]);
    expect(sent).toStrictEqual([]);
  });

  it('pushes the note with the coach named as its squad calls it', async () => {
    const { deps, sent } = setUp([note({ id: 1, member: east, text: 'Easy day today' })]);
    const asked: unknown[] = [];
    const named = {
      ...deps,
      coachNames: (pairs: readonly { coach: string; squad: string | undefined }[]) => {
        asked.push(...pairs);
        return Promise.resolve(() => 'Poki');
      },
    };
    expect(await deliverCoachNotes(named)).toStrictEqual({ waiting: 1, delivered: 1, pushed: 1 });
    expect(asked).toStrictEqual([
      { coach: 'xiaohun', squad: note({ id: 1, member: east, text: '' }).squad },
    ]);
    expect(sent.map(({ notification }) => notification.alert.args)).toStrictEqual([
      ['Poki', 'Easy day today'],
    ]);
  });
});
