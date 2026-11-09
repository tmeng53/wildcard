import { randomUUID } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { MemberId, SquadId } from '../domain/check-in.js';
import { memberWeek } from './check-ins/member-week.js';

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

  it('keeps the member’s own clock without the squad’s', async () => {
    const week = await memberWeek(deps, { member, viewer, squad });
    expect({ weekStart: week.weekStart, today: week.today }).toStrictEqual({
      weekStart: '2026-11-02',
      today: '2026-11-08',
    });
  });
});
