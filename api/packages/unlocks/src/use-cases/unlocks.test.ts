import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresUnlockStore, type UnlockTables } from '../adapters/postgres-unlock-store.js';
import { MemberId, PieceId, type Trained } from '../domain/unlocks.js';
import {
  UnlockItemMissingError,
  UnlockSportNotListedError,
  UnlockStoreMissingError,
  UnlockSwitchMissingError,
} from '../errors.js';
import { createUnlocks } from './unlocks.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<UnlockTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

/**
 * Unlocks over the real tables, with the member's 练了 kept here and each new unlock it tells
 * written to `told`.
 */
function unlocksWith(trained: Map<MemberId, Trained[]>, told: string[] = []) {
  return createUnlocks({
    store: createPostgresUnlockStore(db),
    trainedSince: ({ member, since }) =>
      Promise.resolve((trained.get(member) ?? []).filter(({ madeAt }) => madeAt >= since)),
    sportListed: (id) => Promise.resolve(id !== 'quidditch'),
    // Every switch is off in July (UTC), so a test can train while one is off.
    switches: () => Promise.resolve((_id, at) => at.getUTCMonth() !== 6),
    switchListed: (id) => Promise.resolve(id === 'winter'),
    unlocked: (_member, unlocks) => {
      told.push(...unlocks.map(({ kind, id }) => `${kind}:${id}`));
      return Promise.resolve();
    },
  });
}

describe('unlocks', () => {
  it('starts with a rule for each store and prop that is not a starter', async () => {
    // Other tests add rules of their own, named test….
    const all = (await unlocksWith(new Map()).rules()).filter(({ id }) => !id.startsWith('test'));
    const rules = all.filter(({ kind }) => kind !== 'piece');
    expect(rules.map(({ kind, id, sports, after }) => [kind, id, sports, after])).toStrictEqual([
      ['prop', 'badminton', ['badminton'], 1],
      ['prop', 'basketball', ['basketball'], 1],
      ['prop', 'chalkbag', ['climb'], 1],
      ['prop', 'gloves', ['boxing', 'kickboxing', 'jiuJitsu', 'martialArts'], 1],
      ['prop', 'goggles', ['swim'], 1],
      ['prop', 'helmet', ['roadCycling', 'mountainBiking', 'spin', 'bikeCommute'], 1],
      ['prop', 'kettlebell', ['kettlebell', 'crossfit', 'hyrox'], 1],
      ['prop', 'pickleball', ['pickleball'], 1],
      ['prop', 'pingpong', ['tableTennis'], 1],
      ['prop', 'racket', ['tennis', 'squash'], 1],
      ['prop', 'skis', ['ski', 'crossCountrySki'], 1],
      ['prop', 'snowboard', ['snowboard'], 1],
      ['prop', 'soccerball', ['soccer'], 1],
      ['prop', 'yogamat', ['yoga', 'matPilates', 'reformerPilates', 'barre', 'stretching'], 1],
      ['store', 'deuce', ['tennis', 'pickleball', 'squash'], 3],
      ['store', 'halfmoon', [], 3],
      ['store', 'lap', ['run', 'walk'], 3],
      ['store', 'moss', ['hike', 'trailRun', 'climb'], 3],
      ['store', 'nolook', ['basketball', 'volleyball'], 3],
    ]);
    // Each piece of the second wardrobe opens on its own, in its store's sports.
    const pieces = all.filter(({ kind }) => kind === 'piece');
    expect(pieces).toHaveLength(57);
    expect(
      pieces
        .filter(({ id }) => id.startsWith('lap-'))
        .map(({ id, sports, after }) => [id, sports, after]),
    ).toStrictEqual([
      ['lap-baguette', ['run', 'walk'], 30],
      ['lap-bib', ['run', 'walk'], 5],
      ['lap-runcap', ['run', 'walk'], 20],
      ['lap-singlet', ['run', 'walk'], 7],
      ['lap-spikes', ['run', 'walk'], 10],
      ['lap-split', ['run', 'walk'], 16],
      ['lap-vest', ['run', 'walk'], 25],
      ['lap-wind', ['run', 'walk'], 13],
    ]);
    // POWDER DAY's locked pieces open one a winter-sport 练了, the salmon helmet last.
    const powder = pieces
      .filter(({ id }) => id.startsWith('powder-'))
      .toSorted((a, b) => a.after - b.after);
    expect(powder.map(({ after }) => after)).toStrictEqual([
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    ]);
    expect(powder.at(-1)?.id).toBe('powder-salmonhelmet');
    expect(powder[0]?.sports).toStrictEqual([
      'ski',
      'snowboard',
      'skate',
      'crossCountrySki',
      'curling',
      'snowHike',
      'snowman',
      'snowballFight',
    ]);
  });

  it('keeps each store and piece with its own switch, starters needing no rule', async () => {
    const unlocks = unlocksWith(new Map());
    const stores = await unlocks.stores();
    expect(
      stores.filter(({ id }) => !id.startsWith('test')).map(({ id, switchId }) => [id, switchId]),
    ).toStrictEqual([
      ['warmup', undefined],
      ['lap', undefined],
      ['nolook', undefined],
      ['moss', undefined],
      ['halfmoon', undefined],
      ['deuce', undefined],
      ['powder', 'winter'],
    ]);
    const powder = (await unlocks.pieces()).filter(({ storeId }) => storeId === 'powder');
    expect(powder).toHaveLength(17);
    expect(powder.filter(({ starter }) => starter).map(({ id }) => id)).toStrictEqual([
      'powder-helmet',
      'powder-rice',
      'powder-saba',
      'powder-salmon',
    ]);
    // A piece follows its store's switch; none has one of its own yet.
    expect(powder.every(({ switchId }) => switchId === undefined)).toBe(true);
  });

  it('counts only check-ins made while the store’s switch is on, and shows its rack only then', async () => {
    const unlocks = unlocksWith(new Map());
    const store = `testw${randomUUID().slice(0, 8)}`;
    await unlocks.putStore({ id: store, position: 99, switchId: 'winter', offered: true });
    const starter = `${store}-suit`;
    const board = `${store}-board`;
    await unlocks.putPiece({
      id: starter,
      storeId: store,
      slot: 'top',
      starter: true,
      switchId: null,
      offered: true,
    });
    await unlocks.putPiece({
      id: board,
      storeId: store,
      slot: 'acc',
      starter: false,
      switchId: null,
      offered: true,
    });
    await unlocks.putRule({ kind: 'piece', id: board, sports: ['ski'], after: 1 });
    await expect(
      unlocks.putPiece({
        id: 'testnowhere-cap',
        storeId: 'testnowhere',
        slot: 'hat',
        starter: true,
        switchId: null,
        offered: true,
      }),
    ).rejects.toBeInstanceOf(UnlockStoreMissingError);

    const me = await newMember();
    const july = {
      id: randomUUID(),
      sport: 'ski',
      day: '2099-07-01',
      madeAt: new Date('2099-07-01T12:00:00Z'),
    };
    const december = {
      id: randomUUID(),
      sport: 'ski',
      day: '2099-12-01',
      madeAt: new Date('2099-12-01T12:00:00Z'),
    };
    const trained = new Map<MemberId, Trained[]>([[me, [july]]]);
    const switched = unlocksWith(trained);
    const summer = await switched.standing(me);
    expect(summer.unlocks.some(({ id }) => id === board)).toBe(false);
    expect(summer.locked.find(({ id }) => id === board)?.toGo).toBe(1);
    trained.set(me, [july, december]);
    const winter = await switched.of(me);
    expect(winter.find(({ id }) => id === board)?.by).toStrictEqual({ checkIn: december.id });

    // Whether the rack is out follows the switch now, and today is not in July.
    const today = await switched.standing(me);
    expect(today.shelf.stores.find(({ id }) => id === store)).toStrictEqual({
      id: store,
      open: true,
    });
    expect(
      today.shelf.pieces
        .filter(({ storeId }) => storeId === store)
        .map(({ id, state }) => [id, state]),
    ).toStrictEqual([
      [board, 'owned'],
      // A limited store's starter is the member's while it is out, to claim (领取) and keep.
      [starter, 'owned'],
    ]);
    await switched.claim(me, PieceId.parse(starter));
    // A member whose saved look wears the starter keeps it as claimed; ids that aren't a piece
    // of theirs are skipped, and one who only saw it keeps nothing.
    const wearer = await newMember();
    const passerby = await newMember();
    await switched.keepWorn(wearer, [starter, 'peach', board]);
    expect((await switched.claimsOf(wearer)).map(({ piece }) => piece)).toStrictEqual([starter]);

    // Retired, the store leaves the street and its pieces are boxed for nobody, even one still
    // offered, so other tests count only the seeded ones.
    await unlocks.putStore({ id: store, position: 99, switchId: 'winter', offered: false });
    const retired = await unlocksWith(new Map()).standing(await newMember());
    expect(retired.shelf.stores.some(({ id }) => id === store)).toBe(false);
    expect(retired.locked.some(({ id }) => id === board)).toBe(false);
    // What a member unlocked or claimed there stays theirs, the store listed closed.
    const mine = await switched.standing(me);
    expect(mine.shelf.stores.find(({ id }) => id === store)).toStrictEqual({
      id: store,
      open: false,
    });
    expect(
      mine.shelf.pieces
        .filter(({ storeId }) => storeId === store)
        .map(({ id, state }) => [id, state]),
    ).toStrictEqual([
      [board, 'owned'],
      [starter, 'owned'],
    ]);
    const worn = await switched.standing(wearer);
    expect(worn.shelf.pieces.find(({ id }) => id === starter)?.state).toBe('owned');
    const seen = await switched.standing(passerby);
    expect(seen.shelf.pieces.some(({ id }) => id === starter)).toBe(false);
  });

  it('lets a previewer see and claim what their preview opens, keeping none of it', async () => {
    const unlocks = unlocksWith(new Map());
    const store = `testp${randomUUID().slice(0, 8)}`;
    await unlocks.putStore({ id: store, position: 99, switchId: 'winter', offered: true });
    const starter = `${store}-hat`;
    const sweater = `${store}-sweater`;
    for (const [id, isStarter] of [
      [starter, true],
      [sweater, false],
    ] as const) {
      await unlocks.putPiece({
        id,
        storeId: store,
        slot: isStarter ? 'hat' : 'top',
        starter: isStarter,
        switchId: null,
        offered: true,
      });
    }
    await unlocks.putRule({ kind: 'piece', id: sweater, sports: [], after: 1 });
    const me = await newMember();
    const trained = new Map<MemberId, Trained[]>([
      [me, [{ id: randomUUID(), sport: 'run', madeAt: new Date('2099-12-01T12:00:00Z') }]],
    ]);
    // In the preview the store's switch is on; as really set, it is off.
    const pieceStore = createPostgresUnlockStore(db);
    const previewing = createUnlocks({
      store: pieceStore,
      trainedSince: ({ member }) => Promise.resolve(trained.get(member) ?? []),
      sportListed: () => Promise.resolve(true),
      switches: () => Promise.resolve(() => true),
      keptSwitches: () => Promise.resolve(() => false),
      switchListed: () => Promise.resolve(true),
    });
    const preview = await previewing.standing(me);
    expect(
      preview.shelf.pieces
        .filter(({ storeId }) => storeId === store)
        .map(({ id, state }) => [id, state]),
    ).toStrictEqual([
      [starter, 'owned'],
      [sweater, 'owned'],
    ]);
    expect((await previewing.claim(me, PieceId.parse(starter))).piece).toBe(starter);
    await previewing.keepWorn(me, [starter, sweater]);

    // Once the preview ends, nothing of it is theirs: no grant, no claim, no rack.
    expect((await pieceStore.unlocksOf(me)).some(({ id }) => id === sweater)).toBe(false);
    expect(await previewing.claimsOf(me)).toStrictEqual([]);
    const after = await createUnlocks({
      store: pieceStore,
      trainedSince: ({ member }) => Promise.resolve(trained.get(member) ?? []),
      sportListed: () => Promise.resolve(true),
      switches: () => Promise.resolve(() => false),
      switchListed: () => Promise.resolve(true),
    }).standing(me);
    expect(after.shelf.pieces.some(({ storeId }) => storeId === store)).toBe(false);
    await unlocks.putStore({ id: store, position: 99, switchId: 'winter', offered: false });
  });

  it('refuses a store or piece that follows a switch nobody made', async () => {
    const unlocks = unlocksWith(new Map());
    const store = `testx${randomUUID().slice(0, 8)}`;
    await expect(
      unlocks.putStore({ id: store, position: 99, switchId: 'summer', offered: true }),
    ).rejects.toBeInstanceOf(UnlockSwitchMissingError);
    await unlocks.putStore({ id: store, position: 99, switchId: null, offered: false });
    await expect(
      unlocks.putPiece({
        id: `${store}-cap`,
        storeId: store,
        slot: 'hat',
        starter: true,
        switchId: 'summer',
        offered: false,
      }),
    ).rejects.toBeInstanceOf(UnlockSwitchMissingError);
  });

  it('keeps what a member earned, even once the check-in that earned it is gone', async () => {
    const me = await newMember();
    const trained = new Map<MemberId, Trained[]>();
    const told: string[] = [];
    const unlocks = unlocksWith(trained, told);
    expect(await unlocks.of(me)).toStrictEqual([]);

    const now = Date.now();
    const tennis = [1, 2, 3].map((minutes) => ({
      id: randomUUID(),
      sport: 'tennis',
      // Each on a day of its own, since a rule counts days.
      day: `2099-01-0${String(minutes)}`,
      madeAt: new Date(now + minutes * 60_000),
    }));
    trained.set(me, tennis.slice(0, 1));
    expect((await unlocks.of(me)).map(({ kind, id }) => [kind, id])).toStrictEqual([
      ['prop', 'racket'],
    ]);
    trained.set(me, tennis.slice(0, 2));
    const { unlocks: two, locked } = await unlocks.standing(me);
    // WARM-UP's headphones open on the 2nd 练了 of any sport; the rest show how far they are.
    expect(two.map(({ kind, id }) => [kind, id])).toStrictEqual([
      ['prop', 'racket'],
      ['piece', 'warmup-headphones'],
    ]);
    expect(locked.find(({ id }) => id === 'warmup-stripe')).toStrictEqual({
      kind: 'piece',
      id: 'warmup-stripe',
      toGo: 2,
      sports: [],
    });
    expect(locked.find(({ id }) => id === 'deuce-sweater')?.toGo).toBe(3);
    expect(locked.find(({ id }) => id === 'lap-bib')?.toGo).toBe(5);
    expect(locked.some(({ id }) => id === 'warmup-headphones' || id === 'racket')).toBe(false);
    trained.set(me, tennis);
    const all = await unlocks.of(me);
    expect(all.map(({ kind, id, by }) => [kind, id, by])).toStrictEqual([
      ['prop', 'racket', { checkIn: tennis[0]?.id }],
      ['piece', 'warmup-headphones', { checkIn: tennis[1]?.id }],
      ['store', 'deuce', { checkIn: tennis[2]?.id }],
      // HALF MOON opens after 3 of any sport.
      ['store', 'halfmoon', { checkIn: tennis[2]?.id }],
    ]);
    expect(all[2]?.unlockedAt).toStrictEqual(tennis[2]?.madeAt);
    // Each one told once, when it was new.
    expect(told).toStrictEqual([
      'prop:racket',
      'piece:warmup-headphones',
      'store:deuce',
      'store:halfmoon',
    ]);

    // The posts are deleted: what they unlocked stays.
    trained.set(me, []);
    expect(await unlocks.of(me)).toStrictEqual(all);
    expect(told).toHaveLength(4);
    await expect(
      sql`delete from public.grants where member_id = ${me}`.execute(db),
    ).rejects.toThrow('append-only');
  });

  it('lists every reward with each way it is got, a rule being its training trigger', async () => {
    const unlocks = unlocksWith(new Map());
    const rewards = await unlocks.rewards();
    expect(rewards.find(({ kind, id }) => kind === 'store' && id === 'lap')).toMatchObject({
      triggers: [{ kind: 'training', sports: ['run', 'walk'], after: 3 }],
    });
    const rules = await unlocks.rules();
    expect(
      rewards
        .flatMap(({ kind, id, triggers }) =>
          triggers.filter((each) => each.kind === 'training').map(() => `${kind}:${id}`),
        )
        .sort(),
    ).toStrictEqual(rules.map(({ kind, id }) => `${kind}:${id}`).sort());
  });

  it('logs each rule change, keeps its start, and refuses a sport the list lacks', async () => {
    const unlocks = unlocksWith(new Map());
    const before = await unlocks.rules();
    const id = `test${randomUUID().slice(0, 8)}`;
    const added = await unlocks.putRule({ kind: 'prop', id, sports: ['testOne'], after: 2 });
    const rule = added.find((each) => each.id === id);
    expect(rule).toMatchObject({ kind: 'prop', id, sports: ['testOne'], after: 2 });
    // No check-in names these sports, so the rule never opens for another test's members.
    const changed = await unlocks.putRule({ kind: 'prop', id, sports: ['testTwo'], after: 4 });
    expect(changed.find((each) => each.id === id)).toStrictEqual({
      ...rule,
      sports: ['testTwo'],
      after: 4,
    });
    // The same again changes nothing, so it logs nothing.
    await unlocks.putRule({ kind: 'prop', id, sports: ['testTwo'], after: 4 });
    const events = await sql<{ op: string; value: { after: number } }>`
      select op, value from public.reward_trigger_events where value ->> 'reward_id' = ${id} order by id
    `.execute(db);
    expect(events.rows.map(({ op, value }) => [op, value.after])).toStrictEqual([
      ['INSERT', 2],
      ['UPDATE', 4],
    ]);
    await expect(
      unlocks.putRule({ kind: 'store', id: 'deuce', sports: ['quidditch'], after: 3 }),
    ).rejects.toBeInstanceOf(UnlockSportNotListedError);
    await expect(
      sql`delete from public.reward_triggers where reward_id = ${id}`.execute(db),
    ).rejects.toThrow('never deleted');
    expect(before.length + 1).toBe(changed.length);
  });

  it('gives the picks an admin makes, or every store, prop and piece, keeping what was already earned', async () => {
    const me = await newMember();
    const admin = await newMember();
    const trained = new Map<MemberId, Trained[]>();
    const told: string[] = [];
    const unlocks = unlocksWith(trained, told);
    const racket = {
      id: randomUUID(),
      sport: 'tennis',
      day: '2099-01-01',
      madeAt: new Date(Date.now() + 60_000),
    };
    trained.set(me, [racket]);
    expect(await unlocks.of(me)).toHaveLength(1);

    const picked = await unlocks.give(
      {
        member: me,
        items: [
          { kind: 'store', id: 'deuce' },
          { kind: 'prop', id: 'racket' },
        ],
      },
      admin,
    );
    expect(picked.map(({ kind, id, by }) => [kind, id, by])).toStrictEqual([
      ['store', 'deuce', { admin }],
      ['prop', 'racket', { checkIn: racket.id }],
    ]);
    // A gift is told too, but not what the member held already.
    expect(told).toStrictEqual(['prop:racket', 'store:deuce']);
    await expect(
      unlocks.give({ member: me, items: [{ kind: 'store', id: 'nowhere' }] }, admin),
    ).rejects.toBeInstanceOf(UnlockItemMissingError);
    expect(
      (await unlocks.give({ member: me, items: [{ kind: 'piece', id: 'lap-bib' }] }, admin)).find(
        ({ id }) => id === 'lap-bib',
      ),
    ).toMatchObject({ kind: 'piece', by: { admin } });

    const everything = await unlocks.give({ member: me }, admin);
    expect(everything).toHaveLength((await unlocks.rules()).length);
    expect(await unlocks.of(me)).toStrictEqual(everything);
  });
});
