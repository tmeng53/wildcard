import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresPlaceStore,
  createPostgresWeatherDayStore,
  type WeatherTables,
} from '../adapters/postgres-weather-stores.js';
import { weatherWords, type DayWeather } from '../domain/day-weather.js';
import { MemberId, type Place } from '../domain/place.js';
import type { Forecasts } from '../ports.js';
import { createWeather } from './weather.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<WeatherTables>({
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

/** A cell no other test uses, so the kept days don't cross. */
function freshCell(): Place {
  return {
    latitude: Math.round((Math.random() * 160 - 80) * 10) / 10,
    longitude: Math.round((Math.random() * 340 - 170) * 10) / 10,
  };
}

const RAIN: DayWeather = {
  version: 1,
  condition: 'Rain',
  high: 12.8,
  low: 7.9,
  precipitationChance: 0.82,
};

/** A provider that answers `RAIN` and counts what it was asked. */
function countingForecasts(
  answer: () => Promise<DayWeather | undefined> = () => Promise.resolve(RAIN),
) {
  const asked: { place: Place; day: string; timeZone: string }[] = [];
  const forecasts: Forecasts = {
    dayAt: (input) => {
      asked.push({ ...input });
      return answer();
    },
  };
  return { forecasts, asked };
}

function weatherWith(forecasts?: Forecasts, failed?: (error: unknown) => void) {
  return createWeather({
    places: createPostgresPlaceStore(db),
    days: createPostgresWeatherDayStore(db),
    ...(forecasts === undefined ? {} : { forecasts }),
    clock: () => new Date('2026-11-09T11:00:00Z'),
    ...(failed === undefined ? {} : { failed }),
  });
}

describe('places', () => {
  it('keeps only a 0.1° cell of where the member is, and the latest one', async () => {
    const member = await newMember();
    const weather = weatherWith();
    expect(
      await weather.savePlace(member, { latitude: 40.71283, longitude: -74.00601 }),
    ).toStrictEqual({
      latitude: 40.7,
      longitude: -74,
    });
    await weather.savePlace(member, { latitude: 25.0339, longitude: 121.5645 });
    const rows = await db
      .selectFrom('member_places')
      .select(['latitude', 'longitude'])
      .where('member_id', '=', member)
      .execute();
    expect(rows).toStrictEqual([{ latitude: '25.0', longitude: '121.6' }]);
  });

  it('forgets the place, and forgetting again is fine', async () => {
    const member = await newMember();
    const weather = weatherWith();
    await weather.savePlace(member, { latitude: 1, longitude: 2 });
    await weather.forgetPlace(member);
    await weather.forgetPlace(member);
    const rows = await db
      .selectFrom('member_places')
      .selectAll()
      .where('member_id', '=', member)
      .execute();
    expect(rows).toStrictEqual([]);
  });

  it('goes with the account', async () => {
    const member = await newMember();
    await weatherWith().savePlace(member, { latitude: 1, longitude: 2 });
    await sql`delete from auth.users where id = ${member}`.execute(db);
    const rows = await db
      .selectFrom('member_places')
      .selectAll()
      .where('member_id', '=', member)
      .execute();
    expect(rows).toStrictEqual([]);
  });
});

describe('the day’s weather', () => {
  it('asks once a place a day, whoever shares it, and leaves out members without a place', async () => {
    const [ana, bo, cy] = [await newMember(), await newMember(), await newMember()];
    const cell = freshCell();
    const { forecasts, asked } = countingForecasts();
    const weather = weatherWith(forecasts);
    await weather.savePlace(ana, cell);
    await weather.savePlace(bo, { latitude: cell.latitude + 0.01, longitude: cell.longitude });
    const members = [
      { member: ana, timeZone: 'America/New_York' },
      { member: bo, timeZone: 'America/New_York' },
      { member: cy, timeZone: 'America/New_York' },
    ];
    const first = await weather.dayFor({ members, day: '2026-11-09' });
    expect(Object.fromEntries(first)).toStrictEqual({ [ana]: RAIN, [bo]: RAIN });
    // The next wake that day reads what was kept.
    const again = await weather.dayFor({ members, day: '2026-11-09' });
    expect(again.get(ana)).toStrictEqual(RAIN);
    expect(asked).toStrictEqual([{ place: cell, day: '2026-11-09', timeZone: 'America/New_York' }]);
  });

  it('leaves out a place the provider can’t answer for, and tells why', async () => {
    const member = await newMember();
    const errors: unknown[] = [];
    const { forecasts } = countingForecasts(() =>
      Promise.reject(new Error('WeatherKit answered 503')),
    );
    const weather = weatherWith(forecasts, (error) => errors.push(error));
    await weather.savePlace(member, freshCell());
    const day = await weather.dayFor({
      members: [{ member, timeZone: 'Asia/Taipei' }],
      day: '2026-11-09',
    });
    expect(day.size).toBe(0);
    expect(errors).toStrictEqual([new Error('WeatherKit answered 503')]);
  });

  it('has no weather without a provider', async () => {
    const member = await newMember();
    const weather = weatherWith();
    await weather.savePlace(member, freshCell());
    expect(
      (await weather.dayFor({ members: [{ member, timeZone: 'UTC' }], day: '2026-11-09' })).size,
    ).toBe(0);
  });
});

describe('weatherWords', () => {
  it('says the condition, the low and high, and a real chance of rain', () => {
    expect(weatherWords(RAIN)).toBe('雨，8–13°C，降水概率 82%');
  });

  it('leaves out a small chance and a condition it doesn’t know', () => {
    expect(
      weatherWords({
        version: 1,
        condition: 'SomethingNew',
        high: -0.4,
        low: -6.6,
        precipitationChance: 0.1,
      }),
    ).toBe('-7–0°C');
  });
});
