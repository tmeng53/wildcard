import { sql, type Kysely } from 'kysely';

import { SceneId, type ListedScene } from '../domain/catalog.js';
import type { SceneStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads, as generated from the migrations. */
export type SceneTables = DB;

/** A scene's columns, apart from its id and place. */
function columns(scene: ListedScene) {
  return {
    name_zh_hans: scene.names.zhHans,
    name_en: scene.names.en,
    name_zh_hant: scene.names.zhHant,
    signature: scene.colors.signature,
    on_signature: scene.colors.onSignature,
    wash: scene.colors.wash,
    text_color: scene.colors.text,
    floor: scene.colors.floor,
    offered: scene.offered,
    switch_id: scene.switchId ?? null,
    takeover: scene.takeover === true,
  };
}

/**
 * The scenes on Postgres (`supabase/migrations`, `scenes`). Changes run in the caller's
 * transaction when `db` is one. The table's triggers log each row that changes, so places move
 * in one statement and only rows whose place changed are written.
 */
export function createPostgresSceneStore(db: Kysely<SceneTables>): SceneStore {
  return {
    async list() {
      const rows = await db.selectFrom('scenes').selectAll().orderBy('position').execute();
      return rows.map((row) => ({
        id: SceneId.parse(row.id),
        names: { zhHans: row.name_zh_hans, en: row.name_en, zhHant: row.name_zh_hant },
        colors: {
          signature: row.signature,
          onSignature: row.on_signature,
          wash: row.wash,
          text: row.text_color,
          floor: row.floor,
        },
        offered: row.offered,
        ...(row.switch_id === null ? {} : { switchId: row.switch_id }),
        ...(row.takeover ? { takeover: true } : {}),
      }));
    },

    async save(scene, order) {
      const places = order.map((id, index) => [id, index + 1] as const);
      const position = order.indexOf(scene.id) + 1;
      const existing = await db
        .selectFrom('scenes')
        .select('id')
        .where('id', '=', scene.id)
        .executeTakeFirst();
      // Move the others first (the place is unique, checked at the end of the statement).
      const others = places.filter(([id]) => id !== scene.id);
      if (existing === undefined) {
        await renumber(db, others);
        await db
          .insertInto('scenes')
          .values({ id: scene.id, position, ...columns(scene) })
          .execute();
        return;
      }
      await db.updateTable('scenes').set(columns(scene)).where('id', '=', scene.id).execute();
      await renumber(db, places);
    },
  };
}

/** Gives each scene named in `places` its place, in one statement. */
async function renumber(
  db: Kysely<SceneTables>,
  places: readonly (readonly [string, number])[],
): Promise<void> {
  if (places.length === 0) return;
  const values = sql.join(places.map(([id, position]) => sql`(${id}, ${position}::int)`));
  await sql`
    update public.scenes as scene set position = place.position
    from (values ${values}) as place (id, position)
    where scene.id = place.id and scene.position <> place.position
  `.execute(db);
}
