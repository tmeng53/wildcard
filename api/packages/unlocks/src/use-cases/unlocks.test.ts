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

/** Unlocks over the real tables, with the member's 练了 kept here. */
function unlocksWith(trained: Map<MemberId, Trained[]>) {
  return createUnlocks({
    store: createPostgresUnlockStore(db),
    trainedSince: ({ member, since }) =>
      Promise.resolve((trained.get(member) ?? []).filter(({ madeAt }) => madeAt >= since)),
    sportListed: (id) => Promise.resolve(id !== 'quidditch'),
  });
}

describe('unlocks', () => {
  it('starts with a rule for each store and prop that is not a starter', async () => {
    // Other tests add rules of their own, named test….
    const rules = (await unlocksWith(new Map()).rules()).filter(({ id }) => !id.startsWith('test'));
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
  });

  it('keeps what a member earned, even once the check-in that earned it is gone', async () => {
    const me = await newMember();
    const trained = new Map<MemberId, Trained[]>();
    const unlocks = unlocksWith(trained);
    expect(await unlocks.of(me)).toStrictEqual([]);

    const now = Date.now();
    const tennis = [1, 2, 3].map((minutes) => ({
      id: randomUUID(),
      sport: 'tennis',
      madeAt: new Date(now + minutes * 60_000),
    }));
    trained.set(me, tennis.slice(0, 2));
    expect((await unlocks.of(me)).map(({ kind, id }) => [kind, id])).toStrictEqual([
      ['prop', 'racket'],
    ]);
    trained.set(me, tennis);
    const all = await unlocks.of(me);
    expect(all.map(({ kind, id, by }) => [kind, id, by])).toStrictEqual([
      ['prop', 'racket', { checkIn: tennis[0]?.id }],
      ['store', 'deuce', { checkIn: tennis[2]?.id }],
      // HALF MOON opens after 3 of any sport.
      ['store', 'halfmoon', { checkIn: tennis[2]?.id }],
    ]);
    expect(all[1]?.unlockedAt).toStrictEqual(tennis[2]?.madeAt);

    // The posts are deleted: what they unlocked stays.
    trained.set(me, []);
    expect(await unlocks.of(me)).toStrictEqual(all);
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

  it('gives the picks an admin makes, or every store and prop, keeping what was already earned', async () => {
    const me = await newMember();
    const admin = await newMember();
    const trained = new Map<MemberId, Trained[]>();
    const unlocks = unlocksWith(trained);
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
    await expect(
      unlocks.give({ member: me, items: [{ kind: 'store', id: 'nowhere' }] }, admin),
    ).rejects.toBeInstanceOf(UnlockItemMissingError);

    const everything = await unlocks.give({ member: me }, admin);
    expect(everything).toHaveLength((await unlocks.rules()).length);
    expect(await unlocks.of(me)).toStrictEqual(everything);
  });
});
