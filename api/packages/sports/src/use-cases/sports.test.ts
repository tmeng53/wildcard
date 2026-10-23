import { Kysely, PostgresDialect } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresSportStore, type SportTables } from '../adapters/postgres-sport-store.js';
import { createSports } from './sports.js';

// Local Supabase's database, as scripts/verify.sh passes it in, with the list the migration
// seeds. Never a mocked database.
const db = new Kysely<SportTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

const sports = createSports({ store: createPostgresSportStore(db) });

describe('the sports list', () => {
  it('lists the categories in the picker’s order, each with its sports in order', async () => {
    const { categories } = await sports.catalog();
    expect(categories.map(({ id }) => id)).toEqual([
      'runWalk',
      'strength',
      'cardio',
      'mindBody',
      'water',
      'racket',
      'ball',
      'cycling',
      'outdoorWinter',
      'combat',
      'dance',
      'everyday',
    ]);
    expect(categories.flatMap(({ sports }) => sports)).toHaveLength(52);
    expect(categories[0]).toEqual({
      id: 'runWalk',
      names: { zhHans: '跑走', en: 'Run and walk', zhHant: '跑步健走' },
      sports: [
        {
          id: 'run',
          names: { zhHans: '跑步', en: 'Run', zhHant: '跑步' },
          icon: 'figure.run',
          offered: true,
        },
        {
          id: 'walk',
          names: { zhHans: '快走', en: 'Walk', zhHant: '快走' },
          icon: 'figure.walk',
          offered: true,
        },
        {
          id: 'hike',
          names: { zhHans: '徒步', en: 'Hike', zhHant: '健行' },
          icon: 'figure.hiking',
          offered: true,
        },
        {
          id: 'trailRun',
          names: { zhHans: '越野跑', en: 'Trail run', zhHant: '越野跑' },
          icon: 'figure.run',
          offered: true,
        },
      ],
    });
  });

  it('gives each short list in its order', async () => {
    expect((await sports.catalog()).picks).toEqual({
      signUpCommon: ['swim', 'run', 'strength', 'tennis', 'climb', 'yoga'],
      signUpMore: [
        'roadCycling',
        'matPilates',
        'badminton',
        'hike',
        'basketball',
        'ski',
        'pickleball',
        'dance',
        'boxing',
        'soccer',
      ],
      checkInQuick: ['run', 'strength', 'yoga', 'swim', 'spin', 'hike', 'tennis'],
    });
  });

  it('says which ids are listed sports', async () => {
    expect(await sports.isListed('run')).toBe(true);
    expect(await sports.isListed('trailRun')).toBe(true);
    expect(await sports.isListed('quidditch')).toBe(false);
    expect(await sports.isListed('custom')).toBe(false);
    expect(await sports.isListed('Run')).toBe(false);
    expect(await sports.isListed('')).toBe(false);
  });
});
