import { sql, type Kysely } from 'kysely';
import { z } from 'zod';

import { Place, PlaceKey } from '@wildcard/place-ids';

import type { SavedPlace } from '../domain/saved-place.js';
import type { SavedPlaceStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type SavedPlaceTables = DB;

/** A saved place as its log row keeps it. */
const StoredPlace = z.strictObject({ version: z.literal(1), place: Place });

/** The saved-place store on Postgres (`supabase/migrations`): `saved_place_events` is its log. */
export function createPostgresSavedPlaceStore(db: Kysely<SavedPlaceTables>): SavedPlaceStore {
  return {
    async listFor(member) {
      // Each place's latest row stands; it was saved at the first `saved` row after its last
      // `removed` one, so changing the note keeps when it was saved.
      const { rows } = await sql<{
        place_key: string;
        place: unknown;
        note: string | null;
        saved_at: Date;
      }>`
        with mine as (
          select id, place_key, kind, place, note, at
          from public.saved_place_events
          where member_id = ${member}
        ),
        latest as (
          select distinct on (place_key) place_key, kind, place, note
          from mine
          order by place_key, id desc
        )
        select latest.place_key, latest.place, latest.note, (
          select min(at) from mine
          where mine.place_key = latest.place_key
            and mine.id > coalesce(
              (select max(id) from mine as gone
               where gone.place_key = latest.place_key and gone.kind = 'removed'),
              0)
        ) as saved_at
        from latest
        where latest.kind = 'saved'
        order by saved_at desc, latest.place_key
      `.execute(db);
      return rows.map((row): SavedPlace => ({
        key: PlaceKey.parse(row.place_key),
        place: StoredPlace.parse(row.place).place,
        ...(row.note === null ? {} : { note: row.note }),
        savedAt: new Date(row.saved_at),
      }));
    },

    async save({ member, key, place, note, at }) {
      await db
        .insertInto('saved_place_events')
        .values({
          member_id: member,
          place_key: key,
          kind: 'saved',
          place: JSON.stringify({ version: 1, place }),
          note: note ?? null,
          at,
        })
        .execute();
    },

    async remove({ member, key, at }) {
      await db
        .insertInto('saved_place_events')
        .values({ member_id: member, place_key: key, kind: 'removed', at })
        .execute();
    },
  };
}
