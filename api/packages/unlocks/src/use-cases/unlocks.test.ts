import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresUnlockStore, type UnlockTables } from '../adapters/postgres-unlock-store.js';
import { MemberId, type Trained } from '../domain/unlocks.js';
import { UnlockItemMissingError, UnlockSportNotListedError } from '../errors.js';
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
      ['prop', 'chalkbag', ['climb'], 1],
      ['prop', 'goggles', ['swim'], 1],
      ['prop', 'kettlebell', ['kettlebell', 'crossfit', 'hyrox'], 1],
      ['prop', 'pickleball', ['pickleball'], 1],
      ['prop', 'pingpong', ['tableTennis'], 1],
      ['prop', 'racket', ['tennis', 'squash'], 1],
      ['prop', 'yogamat', ['yoga', 'matPilates', 'reformerPilates', 'barre', 'stretching'], 1],
      ['store', 'deuce', ['tennis', 'pickleball', 'squash'], 3],
      ['store', 'halfmoon', [], 3],
      ['store', 'lap', ['run', 'walk'], 3],
      ['store', 'moss', ['hike', 'trailRun', 'climb'], 3],
      ['store', 'nolook', ['basketball', 'volleyball'], 3],
    ]);
    // Each piece of the second wardrobe opens on its own, in its store's sports.
    const pieces = all.filter(({ kind }) => kind === 'piece');
    expect(pieces).toHaveLength(52);
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
    expect(new Set(powder.map(({ switchId }) => switchId))).toStrictEqual(new Set(['winter']));
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

  it('counts only check-ins made while its switch is on toward a rule with one', async () => {
    const unlocks = unlocksWith(new Map());
    const rule = { kind: 'prop' as const, id: 'testSnowboard', sports: ['ski'], after: 1 };
    await unlocks.putRule({ ...rule, switchId: 'winter' });
    // A change that leaves the switch out keeps it; null makes it count all year.
    const kept = await unlocks.putRule(rule);
    expect(kept.find(({ id }) => id === 'testSnowboard')?.switchId).toBe('winter');
    const allYear = await unlocks.putRule({ ...rule, id: 'testAllYear', switchId: null });
    expect(allYear.find(({ id }) => id === 'testAllYear')?.switchId).toBeUndefined();

    const me = await newMember();
    const july = { id: randomUUID(), sport: 'ski', madeAt: new Date('2099-07-01T12:00:00Z') };
    const december = { id: randomUUID(), sport: 'ski', madeAt: new Date('2099-12-01T12:00:00Z') };
    const trained = new Map<MemberId, Trained[]>([[me, [july]]]);
    const switched = unlocksWith(trained);
    const summer = await switched.standing(me);
    expect(summer.unlocks.some(({ id }) => id === 'testSnowboard')).toBe(false);
    expect(summer.locked.find(({ id }) => id === 'testSnowboard')?.toGo).toBe(1);
    trained.set(me, [july, december]);
    const winter = await switched.of(me);
    expect(winter.find(({ id }) => id === 'testSnowboard')?.by).toStrictEqual({
      checkIn: december.id,
    });
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
      sql`delete from public.member_unlocks where member_id = ${me}`.execute(db),
    ).rejects.toThrow('append-only');
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
      select op, value from public.unlock_rule_events where value ->> 'item_id' = ${id} order by id
    `.execute(db);
    expect(events.rows.map(({ op, value }) => [op, value.after])).toStrictEqual([
      ['INSERT', 2],
      ['UPDATE', 4],
    ]);
    await expect(
      unlocks.putRule({ kind: 'store', id: 'deuce', sports: ['quidditch'], after: 3 }),
    ).rejects.toBeInstanceOf(UnlockSportNotListedError);
    await expect(
      sql`delete from public.unlock_rules where item_id = ${id}`.execute(db),
    ).rejects.toThrow('never deleted');
    expect(before.length + 1).toBe(changed.length);
  });

  it('gives the picks an admin makes, or every store, prop and piece, keeping what was already earned', async () => {
    const me = await newMember();
    const admin = await newMember();
    const trained = new Map<MemberId, Trained[]>();
    const told: string[] = [];
    const unlocks = unlocksWith(trained, told);
    const racket = { id: randomUUID(), sport: 'tennis', madeAt: new Date(Date.now() + 60_000) };
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
