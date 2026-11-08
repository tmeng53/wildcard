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
      'outdoorWinter',
      'winter',
      'combat',
      'dance',
      'everyday',
    ]);
    expect(categories.flatMap(({ sports }) => sports)).toHaveLength(82);
    expect(categories[0]).toEqual({
      id: 'runWalk',
      names: { zhHans: '跑走', en: 'Run and walk', zhHant: '跑步健走' },
      color: '#E65345',
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
        {
          id: 'triathlon',
          names: { zhHans: '铁人三项', en: 'Triathlon', zhHant: '鐵人三項' },
          icon: 'figure.run',
          offered: true,
        },
      ],
    });
  });

  it('gives each category its colour, winter sports their own tab and cycling a place in 有氧', async () => {
    const { categories } = await sports.catalog();
    expect(Object.fromEntries(categories.map(({ id, color }) => [id, color]))).toEqual({
      runWalk: '#E65345',
      strength: '#4A6C8C',
      cardio: '#C8681C',
      mindBody: '#5E8A7A',
      water: '#079BB8',
      racket: '#4F6B22',
      ball: '#1F8A5B',
      outdoorWinter: '#8E4A2C',
      winter: '#2F86C4',
      combat: '#9E2F3A',
      dance: '#7B5E96',
      everyday: '#6A6A8C',
    });
    const ids = (id: string) =>
      categories.find((category) => category.id === id)?.sports.map((sport) => sport.id);
    expect(ids('winter')).toEqual([
      'ski',
      'snowboard',
      'crossCountrySki',
      'skate',
      'curling',
      'snowHike',
      'snowman',
      'snowballFight',
    ]);
    expect(ids('outdoorWinter')).toEqual(['climb', 'archery', 'horseRiding', 'fishing', 'hunting']);
    expect(ids('cardio')?.slice(-4)).toEqual([
      'roadCycling',
      'mountainBiking',
      'stairs',
      'fitnessGaming',
    ]);
  });

  it('gives a long name a shorter one for cards, and leaves the rest without', async () => {
    const all = (await sports.catalog()).categories.flatMap((category) => category.sports);
    expect(all.find((sport) => sport.id === 'tableTennis')?.shortNames).toEqual({
      zhHans: '乒乓球',
      en: 'Ping pong',
      zhHant: '桌球',
    });
    expect(all.find((sport) => sport.id === 'strength')).toMatchObject({
      names: { zhHans: '力量训练', en: 'Strength', zhHant: '重訓' },
    });
    expect(all.find((sport) => sport.id === 'strength')).not.toHaveProperty('shortNames');
  });

  it('gives each short list in its order', async () => {
    expect((await sports.catalog()).picks).toEqual({
      signUpCommon: ['swim', 'run', 'strength', 'tennis', 'climb', 'yoga'],
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
