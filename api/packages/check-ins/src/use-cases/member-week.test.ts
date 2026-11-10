import { randomUUID } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { MemberId, SquadId } from '../domain/check-in.js';
import { WeekStart } from '../domain/weekly-plan.js';
import { memberWeek, planSharedTo } from './check-ins/member-week.js';

// Monday 2026-11-09 at 00:13 in New York: still Sunday the 8th in Los Angeles.
const now = new Date('2026-11-09T05:13:00Z');
const member = MemberId.parse(randomUUID());
const viewer = MemberId.parse(randomUUID());
const squad = SquadId.parse(randomUUID());

const deps = {
  store: { listForMember: () => Promise.resolve([]) },
  plans: {
    savedFor: () => Promise.resolve(undefined),
    templateFor: () => Promise.resolve(undefined),
    trainedBy: () => Promise.resolve({}),
    fuelGoals: () => Promise.resolve(undefined),
  },
  calendarOf: () =>
    Promise.resolve({
      timeZone: 'America/Los_Angeles',
      joinedAt: new Date('2026-10-01T12:00:00Z'),
    }),
  clock: () => now,
};

describe('memberWeek', () => {
  it('shows the week and today on the squad’s clock, so every squadmate sees the same week', async () => {
    const week = await memberWeek(deps, {
      member,
      viewer,
      squad,
      squadZone: 'America/New_York',
    });
    expect({ weekStart: week.weekStart, today: week.today }).toStrictEqual({
      weekStart: '2026-11-09',
      today: '2026-11-09',
    });
  });

  it('shows a day a 练了 the squad can’t see turned as the member planned it', async () => {
    const lift = { kind: 'train', sport: 'strength' } as const;
    const swim = { kind: 'train', sport: 'swim' } as const;
    const train = { kind: 'train' } as const;
    const rest = { kind: 'rest' } as const;
    const week = await memberWeek(
      {
        ...deps,
        plans: {
          ...deps.plans,
          // Tuesday was planned as strength and Wednesday as rest; 练了 sent to no squad turned both.
          savedFor: () => Promise.resolve([train, swim, swim, train, train, train, rest]),
          trainedBy: () =>
            Promise.resolve({
              '1': { checkIn: randomUUID(), from: lift },
              '2': { checkIn: randomUUID(), from: rest },
            }),
        },
      },
      { member, viewer, squad, squadZone: 'America/New_York' },
    );
    expect(week.days.slice(1, 3)).toStrictEqual([lift, rest]);
  });

  it('gives the plan as the squad sees it, for the coach', async () => {
    const lift = { kind: 'train', sport: 'strength' } as const;
    const swim = { kind: 'train', sport: 'swim' } as const;
    const train = { kind: 'train' } as const;
    const rest = { kind: 'rest' } as const;
    const days = await planSharedTo(
      {
        store: deps.store,
        plans: {
          ...deps.plans,
          savedFor: () => Promise.resolve([train, swim, rest, train, train, train, rest]),
          trainedBy: () => Promise.resolve({ '1': { checkIn: randomUUID(), from: lift } }),
        },
      },
      { member, squad, weekStart: WeekStart.parse('2026-11-09') },
    );
    expect(days[1]).toStrictEqual(lift);
  });
});
