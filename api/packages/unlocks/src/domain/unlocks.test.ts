import { describe, expect, it } from 'vitest';

import {
  earned,
  idFits,
  PieceId,
  shelf,
  toGo,
  UnlockRuleEdit,
  type CountedRule,
  type Piece,
  type Store,
} from './unlocks.js';

const start = new Date('2026-11-02T16:00:00Z');
const deuce: CountedRule = {
  kind: 'store',
  id: 'deuce',
  sports: ['tennis', 'pickleball', 'squash'],
  after: 3,
  countsFrom: start,
  switchIds: [],
};
const halfmoon: CountedRule = {
  kind: 'store',
  id: 'halfmoon',
  sports: [],
  after: 3,
  countsFrom: start,
  switchIds: [],
};
const racket: CountedRule = {
  kind: 'prop',
  id: 'racket',
  sports: ['tennis', 'squash'],
  after: 1,
  countsFrom: start,
  switchIds: [],
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
      earned({ rules: [deuce, halfmoon, racket], trained, has: [], switchOn: allYear }),
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
      earned({ rules: [deuce, racket], trained, has: [held], switchOn: allYear }),
    ).toStrictEqual([]);
    expect(
      earned({
        rules: [deuce],
        trained: [...trained, { id: 'e', sport: 'tennis', madeAt: at(6) }],
        has: [],
        switchOn: allYear,
      }),
    ).toMatchObject([{ id: 'deuce', by: { checkIn: 'e' }, unlockedAt: at(6) }]);
  });

  it('never counts a custom sport toward a rule with sports, but does toward any sport', () => {
    const trained = ['a', 'b', 'c'].map((id, index) => ({
      id,
      sport: 'custom',
      madeAt: at(index + 1),
    }));
    expect(earned({ rules: [deuce, halfmoon], trained, has: [], switchOn: allYear })).toMatchObject(
      [{ id: 'halfmoon', by: { checkIn: 'c' } }],
    );
  });
});

describe('toGo', () => {
  it('counts what each rule not yet reached still needs, in its sports, since its start', () => {
    const bib: CountedRule = {
      kind: 'piece',
      id: 'lap-bib',
      sports: ['run', 'walk'],
      after: 5,
      countsFrom: start,
      switchIds: [],
    };
    const trained = [
      { id: 'a', sport: 'run', madeAt: at(-5) },
      { id: 'b', sport: 'run', madeAt: at(1) },
      { id: 'c', sport: 'walk', madeAt: at(2) },
      { id: 'd', sport: 'tennis', madeAt: at(3) },
    ];
    expect(toGo({ rules: [bib, racket, halfmoon], trained, switchOn: allYear })).toStrictEqual([
      { kind: 'piece', id: 'lap-bib', toGo: 3, sports: ['run', 'walk'] },
      // The racket and HALF MOON are reached, so they aren't listed.
    ]);
  });
});

describe('a rule with switches', () => {
  it('counts only check-ins made while all its switches are on', () => {
    const tuna: CountedRule = {
      kind: 'piece',
      id: 'powder-tuna',
      sports: ['ski'],
      after: 2,
      countsFrom: start,
      switchIds: ['winter'],
    };
    // On only from the third hour on.
    const switchOn = (id: string, madeAt: Date) => id === 'winter' && madeAt >= at(180);
    const trained = [
      { id: 'a', sport: 'ski', madeAt: at(60) },
      { id: 'b', sport: 'ski', madeAt: at(120) },
      { id: 'c', sport: 'ski', madeAt: at(200) },
    ];
    expect(earned({ rules: [tuna], trained, has: [], switchOn })).toStrictEqual([]);
    expect(toGo({ rules: [tuna], trained, switchOn })).toStrictEqual([
      { kind: 'piece', id: 'powder-tuna', toGo: 1, sports: ['ski'] },
    ]);
    const more = [...trained, { id: 'd', sport: 'ski', madeAt: at(240) }];
    expect(earned({ rules: [tuna], trained: more, has: [], switchOn })).toMatchObject([
      { id: 'powder-tuna', by: { checkIn: 'd' } },
    ]);
  });
});

describe('shelf', () => {
  const stores: Store[] = [
    { id: 'warmup', position: 1, offered: true },
    { id: 'deuce', position: 2, offered: true },
    { id: 'powder', position: 3, switchId: 'winter', offered: true },
    { id: 'gone', position: 4, offered: false },
  ];
  const piece = (
    id: string,
    { starter = true, switchId }: { starter?: boolean; switchId?: string } = {},
  ): Piece => ({
    id,
    storeId: id.split('-')[0] ?? '',
    slot: 'top',
    starter,
    offered: true,
    ...(switchId === undefined ? {} : { switchId }),
  });
  const pieces = [
    piece('warmup-tee'),
    piece('deuce-polo'),
    piece('powder-salmonsuit'),
    piece('powder-tuna', { starter: false }),
    piece('powder-ikura', { starter: false }),
    piece('warmup-scarf', { switchId: 'winter' }),
    piece('gone-cap'),
  ];
  const tuna: CountedRule = {
    kind: 'piece',
    id: 'powder-tuna',
    sports: ['ski'],
    after: 1,
    countsFrom: start,
    switchIds: ['winter'],
  };
  const ikura = { ...tuna, id: 'powder-ikura', after: 2 };
  const ownedTuna = {
    kind: 'piece' as const,
    id: 'powder-tuna',
    sports: ['ski'],
    after: 1,
    by: { checkIn: 'a' },
    unlockedAt: at(1),
  };
  const rules = [deuce, tuna, ikura];
  const locked = [{ kind: 'piece' as const, id: 'powder-ikura', toGo: 1 }];

  it('shows a closed store’s starters and locked pieces to nobody, and what a member owns all year', () => {
    const off = shelf({ stores, pieces, rules, has: [ownedTuna], locked, on: () => false });
    expect(off.stores).toStrictEqual([
      { id: 'warmup', open: true },
      { id: 'deuce', open: true },
      { id: 'powder', open: false },
    ]);
    expect(off.pieces).toStrictEqual([
      { id: 'warmup-tee', storeId: 'warmup', state: 'available', sports: [], after: 0 },
      // Owned stays on the rack, whatever the switch.
      { id: 'powder-tuna', storeId: 'powder', state: 'owned', sports: ['ski'], after: 1 },
    ]);
  });

  it('puts out an open store’s starters and locked pieces, and a piece on its own switch', () => {
    const on = shelf({ stores, pieces, rules, has: [], locked, on: (id) => id === 'winter' });
    expect(on.stores.find(({ id }) => id === 'powder')?.open).toBe(true);
    expect(on.pieces.map(({ id, state }) => [id, state])).toStrictEqual([
      ['warmup-tee', 'available'],
      // DEUCE CLUB is not earned yet, so its starter waits.
      // A limited starter is the member's while it is out, waiting in its store to be claimed.
      ['powder-salmonsuit', 'owned'],
      // The tuna is reached but not yet kept: it shows once it is owned.
      ['powder-ikura', 'locked'],
      ['warmup-scarf', 'owned'],
    ]);
    expect(on.pieces.find(({ id }) => id === 'powder-ikura')).toMatchObject({
      toGo: 1,
      sports: ['ski'],
      after: 2,
    });
  });
});

describe('shelf, out of season', () => {
  const stores: Store[] = [
    { id: 'powder', position: 1, switchId: 'winter', offered: true },
    { id: 'gone', position: 2, offered: false },
  ];
  const piece = (id: string, starter = true): Piece => ({
    id,
    storeId: id.split('-')[0] ?? '',
    slot: 'top',
    starter,
    offered: true,
  });
  const pieces = [piece('powder-salmonsuit'), piece('powder-rice'), piece('gone-cap', false)];
  const gotCap = {
    kind: 'piece' as const,
    id: 'gone-cap',
    sports: [],
    after: 3,
    by: { checkIn: 'a' },
    unlockedAt: at(1),
  };

  it('keeps a limited starter the member claimed once its switch is off, and drops the rest', () => {
    const off = shelf({
      stores,
      pieces,
      rules: [],
      has: [],
      claimed: [PieceId.parse('powder-salmonsuit')],
      locked: [],
      on: () => false,
    });
    expect(off.pieces.map(({ id, state }) => [id, state])).toStrictEqual([
      ['powder-salmonsuit', 'owned'],
    ]);
  });

  it('keeps what a member unlocked in a retired store, listing the store closed', () => {
    const shown = shelf({ stores, pieces, rules: [], has: [gotCap], locked: [], on: () => false });
    expect(shown.stores).toStrictEqual([
      { id: 'powder', open: false },
      { id: 'gone', open: false },
    ]);
    expect(shown.pieces.map(({ id, state }) => [id, state])).toStrictEqual([['gone-cap', 'owned']]);
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
