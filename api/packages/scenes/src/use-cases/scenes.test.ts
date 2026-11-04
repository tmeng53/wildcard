import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresSceneStore, type SceneTables } from '../adapters/postgres-scene-store.js';
import { SceneNotFoundError } from '../errors.js';
import { createScenes } from './scenes.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Each test changes the seeded
// scenes inside a transaction it rolls back, so other test files keep reading the seed.
const db = new Kysely<SceneTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

class RolledBack extends Error {}

async function rolledBack(test: (trx: Kysely<SceneTables>) => Promise<void>) {
  await expect(
    db.transaction().execute(async (trx) => {
      await test(trx);
      throw new RolledBack();
    }),
  ).rejects.toBeInstanceOf(RolledBack);
}

async function logCount(trx: Kysely<SceneTables>) {
  const { rows } = await sql<{ n: number }>`
    select count(*)::int as n from public.scene_catalog_events
  `.execute(trx);
  return rows[0]?.n ?? 0;
}

const colors = {
  signature: '#E0533E',
  onSignature: '#FFFFFF',
  wash: '#FBEAE7',
  text: '#A63A2B',
  floor: '#F5D9D3',
};

describe('the scenes', () => {
  it('starts with the five scenes and the winter 雪场, open 11/15 to 3/31', async () => {
    const scenes = createScenes({ store: createPostgresSceneStore(db) });
    const list = await scenes.list();
    expect(list.map(({ id }) => id)).toEqual(['track', 'pool', 'gym', 'tennis', 'climbing', 'ski']);
    expect(list.find(({ id }) => id === 'ski')).toMatchObject({
      names: { zhHans: '雪场', en: 'Ski', zhHant: '雪場' },
      colors: { signature: '#16384D', onSignature: '#D6F1FB' },
      window: { start: '11-15', end: '03-31' },
    });
    expect(list.find(({ id }) => id === 'gym')?.window).toBeUndefined();
  });

  it('opens the 雪场 only in its window', async () => {
    const scenes = createScenes({ store: createPostgresSceneStore(db) });
    expect(await scenes.openOn('2026-11-09')).not.toContain('ski');
    expect(await scenes.openOn('2026-11-16')).toContain('ski');
    expect(await scenes.openOn('2027-03-30')).toContain('ski');
    expect(await scenes.openOn('2027-04-06')).toEqual([
      'track',
      'pool',
      'gym',
      'tennis',
      'climbing',
    ]);
  });

  it('adds a scene at its place, logs it, and changes a window alone', async () => {
    await rolledBack(async (trx) => {
      const scenes = createScenes({ store: createPostgresSceneStore(trx) });
      const before = await logCount(trx);
      const added = await scenes.putScene({
        id: 'beach',
        names: { zhHans: '沙滩', en: 'Beach', zhHant: '沙灘' },
        colors,
        offered: true,
        window: { start: '06-01', end: '08-31' },
        position: 2,
      });
      expect(added.map(({ id }) => id)).toEqual([
        'track',
        'beach',
        'pool',
        'gym',
        'tennis',
        'climbing',
        'ski',
      ]);
      // The new row, and the five it moved down.
      expect((await logCount(trx)) - before).toBe(6);

      const reopened = await scenes.setWindow({
        id: 'ski',
        window: { start: '12-01', end: '03-15' },
      });
      expect(reopened.find(({ id }) => id === 'ski')?.window).toEqual({
        start: '12-01',
        end: '03-15',
      });
      expect((await logCount(trx)) - before).toBe(7);

      const allYear = await scenes.setWindow({ id: 'beach', window: null });
      expect(allYear.find(({ id }) => id === 'beach')?.window).toBeUndefined();
      // Saving the same again writes nothing.
      await scenes.setWindow({ id: 'beach', window: null });
      expect((await logCount(trx)) - before).toBe(8);
    });
  });

  it('refuses a window for a scene it doesn’t have', async () => {
    const scenes = createScenes({ store: createPostgresSceneStore(db) });
    await expect(scenes.setWindow({ id: 'moon', window: null })).rejects.toBeInstanceOf(
      SceneNotFoundError,
    );
  });

  it('never deletes a scene or changes its id', async () => {
    await expect(db.deleteFrom('scenes').where('id', '=', 'gym').execute()).rejects.toThrow(
      /never deleted/,
    );
    await expect(
      db.updateTable('scenes').set({ id: 'gym2' }).where('id', '=', 'gym').execute(),
    ).rejects.toThrow(/never changes/);
  });
});
