import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresSportStore, type SportTables } from '../adapters/postgres-sport-store.js';
import type { SportEdit } from '../domain/edits.js';
import { createSports } from './sports.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Each test changes the seeded
// list inside a transaction it rolls back, so the other test files keep reading the seed.
const db = new Kysely<SportTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

class RolledBack extends Error {}

async function rolledBack(test: (trx: Kysely<SportTables>) => Promise<void>) {
  await expect(
    db.transaction().execute(async (trx) => {
      await test(trx);
      throw new RolledBack();
    }),
  ).rejects.toBeInstanceOf(RolledBack);
}

/** The log rows written so far in this transaction, oldest first. */
async function logged(trx: Kysely<SportTables>, since: number) {
  const { rows } = await sql<{ kind: string; op: string; id: string; position: number }>`
    select kind, op, coalesce(value ->> 'sport_id', value ->> 'id') as id,
      (value ->> 'position')::int as position
    from public.sport_catalog_events where id > ${since} order by id
  `.execute(trx);
  return rows.map(({ kind, op, id, position }) => ({ kind, op, id, position }));
}

async function lastLogId(trx: Kysely<SportTables>) {
  const { rows } = await sql<{ id: string | null }>`
    select max(id)::text as id from public.sport_catalog_events
  `.execute(trx);
  return Number(rows[0]?.id ?? 0);
}

const roundnet: SportEdit = {
  id: 'roundnet',
  category: 'racket',
  names: { zhHans: '圆网球', en: 'Roundnet', zhHant: '圓網球' },
  icon: 'figure.volleyball',
  offered: true,
};

const idsIn = async (sports: ReturnType<typeof createSports>, category: string) =>
  (await sports.catalog()).categories.find(({ id }) => id === category)?.sports.map(({ id }) => id);

describe('changing the sports list', () => {
  it('adds a sport at its place, moving only the sports after it, and logs each row once', async () => {
    await rolledBack(async (trx) => {
      const sports = createSports({ store: createPostgresSportStore(trx) });
      const before = await idsIn(sports, 'racket');
      const since = await lastLogId(trx);
      const after = await sports.putSport({ ...roundnet, position: 2 });
      const racket = after.categories.find(({ id }) => id === 'racket')?.sports;
      expect(racket?.map(({ id }) => id)).toEqual([
        before?.[0],
        'roundnet',
        ...(before ?? []).slice(1),
      ]);
      expect(racket?.[1]).toEqual({
        id: 'roundnet',
        names: { zhHans: '圆网球', en: 'Roundnet', zhHant: '圓網球' },
        icon: 'figure.volleyball',
        offered: true,
      });
      const log = await logged(trx, since);
      expect(log.filter(({ op }) => op === 'INSERT')).toEqual([
        { kind: 'sports', op: 'INSERT', id: 'roundnet', position: 2 },
      ]);
      // Every sport after it moved down one, and nothing else was written.
      expect(log.filter(({ op }) => op === 'UPDATE').map(({ id }) => id)).toEqual(
        expect.arrayContaining((before ?? []).slice(1)),
      );
      expect(log).toHaveLength(before?.length ?? 0);
    });
  });

  it('puts a new sport last when no place is given, and swaps places in one change', async () => {
    await rolledBack(async (trx) => {
      const sports = createSports({ store: createPostgresSportStore(trx) });
      await sports.putSport(roundnet);
      expect(await idsIn(sports, 'racket')).toEqual([
        'tennis',
        'badminton',
        'pickleball',
        'tableTennis',
        'squash',
        'roundnet',
      ]);
      await sports.putSport({ ...roundnet, position: 1 });
      expect((await idsIn(sports, 'racket'))?.[0]).toBe('roundnet');
    });
  });

  it('moves a sport to another tab and closes the gap it left', async () => {
    await rolledBack(async (trx) => {
      const sports = createSports({ store: createPostgresSportStore(trx) });
      const catalog = await sports.catalog();
      const walk = catalog.categories[0]?.sports.find(({ id }) => id === 'walk');
      if (walk === undefined) throw new Error('walk is seeded');
      await sports.putSport({ ...walk, category: 'everyday', position: 1 });
      expect(await idsIn(sports, 'runWalk')).toEqual(['run', 'hike', 'trailRun']);
      expect((await idsIn(sports, 'everyday'))?.[0]).toBe('walk');
      const { rows } = await sql<{ category_id: string; positions: number[] }>`
        select category_id, array_agg(position order by position) as positions
        from public.sports where category_id in ('runWalk', 'everyday') group by category_id
      `.execute(trx);
      for (const { positions } of rows) {
        expect(positions).toEqual(positions.map((_, index) => index + 1));
      }
    });
  });

  it('removes short names left out, and writes nothing for a change that changes nothing', async () => {
    await rolledBack(async (trx) => {
      const sports = createSports({ store: createPostgresSportStore(trx) });
      const catalog = await sports.catalog();
      const tableTennis = catalog.categories
        .flatMap((category) =>
          category.sports.map((sport) => ({ ...sport, category: category.id })),
        )
        .find(({ id }) => id === 'tableTennis');
      expect(tableTennis?.shortNames).toEqual({
        zhHans: '乒乓球',
        en: 'Ping pong',
        zhHant: '桌球',
      });
      if (tableTennis === undefined) throw new Error('tableTennis is seeded');
      const since = await lastLogId(trx);
      await sports.putSport(tableTennis);
      expect(await logged(trx, since)).toEqual([]);
      const { id, category, names, icon, offered } = tableTennis;
      const after = await sports.putSport({ id, category, names, icon, offered });
      expect(
        after.categories.flatMap(({ sports }) => sports).find(({ id }) => id === 'tableTennis'),
      ).not.toHaveProperty('shortNames');
      expect(await logged(trx, since)).toHaveLength(1);
    });
  });

  it('refuses a sport in a tab the list doesn’t have', async () => {
    await rolledBack(async (trx) => {
      const sports = createSports({ store: createPostgresSportStore(trx) });
      await expect(sports.putSport({ ...roundnet, category: 'quidditch' })).rejects.toMatchObject({
        reason: 'SPORT_CATEGORY_NOT_FOUND',
      });
    });
  });

  it('retires a sport only once no short list shows it, and keeps it listed', async () => {
    await rolledBack(async (trx) => {
      const sports = createSports({ store: createPostgresSportStore(trx) });
      const catalog = await sports.catalog();
      const climb = catalog.categories
        .flatMap((category) =>
          category.sports.map((sport) => ({ ...sport, category: category.id })),
        )
        .find(({ id }) => id === 'climb');
      if (climb === undefined) throw new Error('climb is seeded');
      await expect(sports.putSport({ ...climb, offered: false })).rejects.toMatchObject({
        reason: 'SPORT_IN_PICK_LIST',
      });
      await sports.setPicks({
        list: 'signUpCommon',
        sports: ['swim', 'run', 'strength', 'tennis', 'yoga'],
      });
      await sports.putSport({ ...climb, offered: false });
      expect(await sports.isListed('climb')).toBe(true);
      await expect(
        sports.setPicks({ list: 'checkInQuick', sports: ['run', 'climb'] }),
      ).rejects.toMatchObject({ reason: 'SPORT_NOT_OFFERED' });
    });
  });

  it('replaces a short list in order, logging only the rows that changed', async () => {
    await rolledBack(async (trx) => {
      const sports = createSports({ store: createPostgresSportStore(trx) });
      const since = await lastLogId(trx);
      const after = await sports.setPicks({
        list: 'checkInQuick',
        sports: ['strength', 'run', 'yoga', 'swim', 'spin', 'hike', 'climb'],
      });
      expect(after.picks.checkInQuick).toEqual([
        'strength',
        'run',
        'yoga',
        'swim',
        'spin',
        'hike',
        'climb',
      ]);
      expect(after.picks.signUpCommon).toEqual([
        'swim',
        'run',
        'strength',
        'tennis',
        'climb',
        'yoga',
      ]);
      const log = await logged(trx, since);
      expect(log.map(({ op, id }) => `${op} ${id}`).sort()).toEqual(
        ['DELETE tennis', 'INSERT climb', 'UPDATE run', 'UPDATE strength'].sort(),
      );
      await expect(
        sports.setPicks({ list: 'checkInQuick', sports: ['quidditch'] }),
      ).rejects.toMatchObject({ reason: 'SPORT_NOT_OFFERED' });
    });
  });

  it('adds a tab and moves one, swapping places', async () => {
    await rolledBack(async (trx) => {
      const sports = createSports({ store: createPostgresSportStore(trx) });
      const names = { zhHans: '新', en: 'New', zhHant: '新' };
      const added = await sports.putCategory({ id: 'brandNew', names, position: 1 });
      expect(added.categories[0]).toEqual({ id: 'brandNew', names, sports: [] });
      expect(added.categories[1]?.id).toBe('runWalk');
      const moved = await sports.putCategory({
        id: 'runWalk',
        names: { zhHans: '跑走', en: 'Run and walk', zhHant: '跑步健走' },
        position: 1,
      });
      expect(moved.categories.slice(0, 2).map(({ id }) => id)).toEqual(['runWalk', 'brandNew']);
      expect(moved.categories).toHaveLength(13);
    });
  });
});
