import { sql, type Kysely } from 'kysely';

import { DayWeather } from '../domain/day-weather.js';
import type { MemberId, Place } from '../domain/place.js';
import type { PlaceStore, WeatherDayStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables these stores read and write, as generated from the migrations. */
export type WeatherTables = DB;

/** Members' places on Postgres (`supabase/migrations`): one row a member, the latest. */
export function createPostgresPlaceStore(db: Kysely<WeatherTables>): PlaceStore {
  return {
    async save(member, { latitude, longitude }, at) {
      await db
        .insertInto('member_places')
        .values({ member_id: member, latitude, longitude, updated_at: at })
        .onConflict((conflict) =>
          conflict.column('member_id').doUpdateSet({ latitude, longitude, updated_at: at }),
        )
        .execute();
    },

    async remove(member) {
      await db.deleteFrom('member_places').where('member_id', '=', member).execute();
    },

    async placesOf(members) {
      if (members.length === 0) return new Map();
      const rows = await db
        .selectFrom('member_places')
        .select(['member_id', 'latitude', 'longitude'])
        .where('member_id', 'in', members)
        .execute();
      return new Map(
        rows.map((row) => [
          row.member_id as MemberId,
          { latitude: Number(row.latitude), longitude: Number(row.longitude) },
        ]),
      );
    },
  };
}

/** The days' weather on Postgres, one row a place a day, kept a week. */
export function createPostgresWeatherDayStore(db: Kysely<WeatherTables>): WeatherDayStore {
  return {
    async find({ latitude, longitude }: Place, day) {
      const row = await db
        .selectFrom('weather_days')
        .select('weather')
        .where('latitude', '=', String(latitude))
        .where('longitude', '=', String(longitude))
        .where('day', '=', day)
        .executeTakeFirst();
      if (row === undefined) return undefined;
      // A row saved in a shape this build can't read is fetched again.
      const parsed = DayWeather.safeParse(row.weather);
      return parsed.success ? parsed.data : undefined;
    },

    async save({ latitude, longitude }, day, weather) {
      await db
        .insertInto('weather_days')
        .values({ latitude, longitude, day, weather: JSON.stringify(weather) })
        .onConflict((conflict) =>
          conflict.columns(['latitude', 'longitude', 'day']).doUpdateSet({
            weather: JSON.stringify(weather),
            fetched_at: sql`now()`,
          }),
        )
        .execute();
      await db
        .deleteFrom('weather_days')
        .where('day', '<', sql<string>`${day}::date - 7`)
        .execute();
    },
  };
}
