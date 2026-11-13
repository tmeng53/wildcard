import type { Kysely, Selectable } from 'kysely';

import { MemberId } from '../domain/ids.js';
import { SquadId, SquadPlaceId, SquadPlaceKind, type SquadPlace } from '../domain/squad-place.js';
import type { SquadPlaceStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type SquadPlaceTables = DB;

function placeOf(row: Selectable<DB['squad_places']>): SquadPlace {
  return {
    id: SquadPlaceId.parse(row.id),
    squad: SquadId.parse(row.squad_id),
    addedBy: row.added_by === null ? undefined : MemberId.parse(row.added_by),
    name: row.name,
    kind: SquadPlaceKind.parse(row.kind),
    latitude: row.latitude,
    longitude: row.longitude,
    addedAt: new Date(row.added_at),
  };
}

/** The squad place store on Postgres (`supabase/migrations`). */
export function createPostgresSquadPlaceStore(db: Kysely<SquadPlaceTables>): SquadPlaceStore {
  return {
    async add(place) {
      const added = await db
        .insertInto('squad_places')
        .values({
          id: place.id,
          squad_id: place.squad,
          added_by: place.addedBy ?? null,
          name: place.name,
          kind: place.kind,
          latitude: place.latitude,
          longitude: place.longitude,
          added_at: place.addedAt.toISOString(),
        })
        .onConflict((conflict) => conflict.column('id').doNothing())
        .returning('id')
        .executeTakeFirst();
      return added === undefined ? 'exists' : 'created';
    },

    async find(id) {
      const row = await db
        .selectFrom('squad_places')
        .selectAll()
        .where('id', '=', id)
        .executeTakeFirst();
      return row === undefined ? undefined : placeOf(row);
    },

    async listForSquad(squad) {
      const rows = await db
        .selectFrom('squad_places')
        .selectAll()
        .where('squad_id', '=', squad)
        .orderBy('added_at')
        .orderBy('id')
        .execute();
      return rows.map(placeOf);
    },
  };
}
