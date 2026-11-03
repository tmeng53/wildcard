import { describe, expect, it } from 'vitest';

import { earned, type UnlockRule } from './unlocks.js';

const start = new Date('2026-11-02T16:00:00Z');
const deuce: UnlockRule = {
  kind: 'store',
  id: 'deuce',
  sports: ['tennis', 'pickleball', 'squash'],
  after: 3,
  countsFrom: start,
};
const halfmoon: UnlockRule = {
  kind: 'store',
  id: 'halfmoon',
  sports: [],
  after: 3,
  countsFrom: start,
};
const racket: UnlockRule = {
  kind: 'prop',
  id: 'racket',
  sports: ['tennis', 'squash'],
  after: 1,
  countsFrom: start,
};
const at = (minutes: number) => new Date(start.getTime() + minutes * 60_000);

describe('earned', () => {
  it('opens a rule on its after-th check-in in its sports, at that check-in', () => {
    const trained = [
      { id: 'a', sport: 'tennis', madeAt: at(1) },
      { id: 'b', sport: 'run', madeAt: at(2) },
      { id: 'c', sport: 'pickleball', madeAt: at(3) },
      { id: 'd', sport: 'squash', madeAt: at(4) },
    ];
    expect(earned({ rules: [deuce, halfmoon, racket], trained, has: [] })).toStrictEqual([
      {
        kind: 'store',
        id: 'deuce',
        sports: ['tennis', 'pickleball', 'squash'],
        after: 3,
        by: { checkIn: 'd' },
        unlockedAt: at(4),
      },
      {
        kind: 'store',
        id: 'halfmoon',
        sports: [],
        after: 3,
        by: { checkIn: 'c' },
        unlockedAt: at(3),
      },
      {
        kind: 'prop',
        id: 'racket',
        sports: ['tennis', 'squash'],
        after: 1,
        by: { checkIn: 'a' },
        unlockedAt: at(1),
      },
    ]);
  });

  it('leaves out check-ins made before the rule counts from, and what is already held', () => {
    const trained = [
      { id: 'a', sport: 'tennis', madeAt: at(-60) },
      { id: 'b', sport: 'tennis', madeAt: at(-1) },
      { id: 'c', sport: 'tennis', madeAt: at(0) },
      { id: 'd', sport: 'tennis', madeAt: at(5) },
    ];
    const held = {
      kind: 'prop' as const,
      id: 'racket',
      sports: ['tennis'],
      after: 1,
      by: { checkIn: 'x' },
      unlockedAt: at(-100),
    };
    expect(earned({ rules: [deuce, racket], trained, has: [held] })).toStrictEqual([]);
    expect(
      earned({
        rules: [deuce],
        trained: [...trained, { id: 'e', sport: 'tennis', madeAt: at(6) }],
        has: [],
      }),
    ).toMatchObject([{ id: 'deuce', by: { checkIn: 'e' }, unlockedAt: at(6) }]);
  });

  it('never counts a custom sport toward a rule with sports, but does toward any sport', () => {
    const trained = ['a', 'b', 'c'].map((id, index) => ({
      id,
      sport: 'custom',
      madeAt: at(index + 1),
    }));
    expect(earned({ rules: [deuce, halfmoon], trained, has: [] })).toMatchObject([
      { id: 'halfmoon', by: { checkIn: 'c' } },
    ]);
  });
});
