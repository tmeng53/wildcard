import type { Kysely } from 'kysely';

import { MemberId, PlaceKey, Stars } from '../domain/place-rating.js';
import type { PlaceRatingStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type PlaceRatingTables = DB;

/** The place rating store on Postgres (`supabase/migrations`). */
export function createPostgresPlaceRatingStore(db: Kysely<PlaceRatingTables>): PlaceRatingStore {
  async function latestRows(places: readonly string[], members: readonly string[]) {
    return db
      .selectFrom('place_ratings')
      .select(['place_key', 'member_id', 'stars'])
      .distinctOn(['place_key', 'member_id'])
      .where('place_key', 'in', places)
      .where('member_id', 'in', members)
      .orderBy('place_key')
      .orderBy('member_id')
      .orderBy('at', 'desc')
      .orderBy('id', 'desc')
      .execute();
  }

  return {
    async add({ member, place, stars, at }) {
      await db
        .insertInto('place_ratings')
        .values({ member_id: member, place_key: place, stars, at })
        .execute();
    },

    async latest({ place, members }) {
      const rows = await latestRows([place], members);
      return new Map(rows.map((row) => [MemberId.parse(row.member_id), Stars.parse(row.stars)]));
    },

    async latestForAll({ places, members }) {
      const rows = await latestRows(places, members);
      const byPlace = new Map<PlaceKey, Map<MemberId, Stars>>();
      for (const row of rows) {
        const place = PlaceKey.parse(row.place_key);
        const scores = byPlace.get(place) ?? new Map<MemberId, Stars>();
        scores.set(MemberId.parse(row.member_id), Stars.parse(row.stars));
        byPlace.set(place, scores);
      }
      return byPlace;
    },
  };
}
