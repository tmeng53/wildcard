import { describe, expect, it } from 'vitest';

import { earned, idFits, toGo, UnlockRuleEdit, type UnlockRule } from './unlocks.js';

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
const allYear = () => true;

describe('earned', () => {
  it('opens a rule on its after-th check-in in its sports, at that check-in', () => {
    const trained = [
      { id: 'a', sport: 'tennis', madeAt: at(1) },
      { id: 'b', sport: 'run', madeAt: at(2) },
      { id: 'c', sport: 'pickleball', madeAt: at(3) },
      { id: 'd', sport: 'squash', madeAt: at(4) },
    ];
    expect(
      earned({ rules: [deuce, halfmoon, racket], trained, has: [], inSeason: allYear }),
    ).toStrictEqual([
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
    expect(
      earned({ rules: [deuce, racket], trained, has: [held], inSeason: allYear }),
    ).toStrictEqual([]);
    expect(
      earned({
        rules: [deuce],
        trained: [...trained, { id: 'e', sport: 'tennis', madeAt: at(6) }],
        has: [],
        inSeason: allYear,
      }),
    ).toMatchObject([{ id: 'deuce', by: { checkIn: 'e' }, unlockedAt: at(6) }]);
  });

  it('never counts a custom sport toward a rule with sports, but does toward any sport', () => {
    const trained = ['a', 'b', 'c'].map((id, index) => ({
      id,
      sport: 'custom',
      madeAt: at(index + 1),
    }));
    expect(earned({ rules: [deuce, halfmoon], trained, has: [], inSeason: allYear })).toMatchObject(
      [{ id: 'halfmoon', by: { checkIn: 'c' } }],
    );
  });
});

describe('toGo', () => {
  it('counts what each rule not yet reached still needs, in its sports, since its start', () => {
    const bib: UnlockRule = {
      kind: 'piece',
      id: 'lap-bib',
      sports: ['run', 'walk'],
      after: 5,
      countsFrom: start,
    };
    const trained = [
      { id: 'a', sport: 'run', madeAt: at(-5) },
      { id: 'b', sport: 'run', madeAt: at(1) },
      { id: 'c', sport: 'walk', madeAt: at(2) },
      { id: 'd', sport: 'tennis', madeAt: at(3) },
    ];
    expect(toGo({ rules: [bib, racket, halfmoon], trained, inSeason: allYear })).toStrictEqual([
      { kind: 'piece', id: 'lap-bib', toGo: 3 },
      // The racket and HALF MOON are reached, so they aren't listed.
    ]);
  });
});

describe('a seasonal rule', () => {
  it('counts only check-ins made in its scene’s season', () => {
    const tuna: UnlockRule = {
      kind: 'piece',
      id: 'powder-tuna',
      sports: ['ski'],
      after: 2,
      countsFrom: start,
      season: 'ski',
    };
    // In season only from the third hour on.
    const inSeason = (scene: string, madeAt: Date) => scene === 'ski' && madeAt >= at(180);
    const trained = [
      { id: 'a', sport: 'ski', madeAt: at(60) },
      { id: 'b', sport: 'ski', madeAt: at(120) },
      { id: 'c', sport: 'ski', madeAt: at(200) },
    ];
    expect(earned({ rules: [tuna], trained, has: [], inSeason })).toStrictEqual([]);
    expect(toGo({ rules: [tuna], trained, inSeason })).toStrictEqual([
      { kind: 'piece', id: 'powder-tuna', toGo: 1 },
    ]);
    const more = [...trained, { id: 'd', sport: 'ski', madeAt: at(240) }];
    expect(earned({ rules: [tuna], trained: more, has: [], inSeason })).toMatchObject([
      { id: 'powder-tuna', by: { checkIn: 'd' } },
    ]);
  });
});

describe('piece ids', () => {
  it('fit only their own kind', () => {
    expect(idFits('piece', 'lap-bib')).toBe(true);
    expect(idFits('piece', 'lap')).toBe(false);
    expect(idFits('store', 'lap-bib')).toBe(false);
    expect(idFits('prop', 'racket')).toBe(true);
    expect(
      UnlockRuleEdit.safeParse({ kind: 'store', id: 'lap-bib', sports: [], after: 3 }).success,
    ).toBe(false);
    expect(
      UnlockRuleEdit.safeParse({ kind: 'piece', id: 'lap-bib', sports: [], after: 3 }).success,
    ).toBe(true);
  });
});
