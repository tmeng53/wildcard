import { SportId } from '@wildcard/sport-ids';
import { sql, type Kysely } from 'kysely';
import { z } from 'zod';

import { PICK_LISTS, type PickList, type SportCatalog } from '../domain/catalog.js';
import type { SportRecord, SportStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads, as generated from the migrations. */
export type SportTables = DB;

const PickListName = z.enum(PICK_LISTS);

/** A sport's card name, when it has one: the table keeps all three languages or none. */
function shortNamesOf(sport: {
  short_name_zh_hans: string | null;
  short_name_en: string | null;
  short_name_zh_hant: string | null;
}): { shortNames?: { zhHans: string; en: string; zhHant: string } } {
  const { short_name_zh_hans: zhHans, short_name_en: en, short_name_zh_hant: zhHant } = sport;
  return zhHans !== null && en !== null && zhHant !== null
    ? { shortNames: { zhHans, en, zhHant } }
    : {};
}

/** A sport's columns, apart from its id and place. */
function sportColumns(sport: SportRecord) {
  return {
    category_id: sport.category,
    icon: sport.icon,
    name_zh_hans: sport.names.zhHans,
    name_en: sport.names.en,
    name_zh_hant: sport.names.zhHant,
    short_name_zh_hans: sport.shortNames?.zhHans ?? null,
    short_name_en: sport.shortNames?.en ?? null,
    short_name_zh_hant: sport.shortNames?.zhHant ?? null,
    offered: sport.offered,
  };
}

/**
 * The sports list on Postgres (`supabase/migrations`). Changes run in the caller's transaction
 * when `db` is one. The table triggers log each row that changes, so a place is moved in one
 * statement and only rows whose place changed are written.
 */
export function createPostgresSportStore(db: Kysely<SportTables>): SportStore {
  /** Gives each row of `table` named in `places` its place, in one statement. */
  async function renumber(
    table: 'sports' | 'sport_categories',
    places: readonly (readonly [string, number])[],
  ) {
    if (places.length === 0) return;
    const values = sql.join(places.map(([id, position]) => sql`(${id}, ${position}::int)`));
    await sql`
      update ${sql.table(table)} as item set position = place.position
      from (values ${values}) as place (id, position)
      where item.id = place.id and item.position <> place.position
    `.execute(db);
  }
  const numbered = (ids: readonly string[]) => ids.map((id, index) => [id, index + 1] as const);

  return {
    async catalog() {
      const [categories, sports, picks] = await Promise.all([
        db.selectFrom('sport_categories').selectAll().orderBy('position').execute(),
        db.selectFrom('sports').selectAll().orderBy('category_id').orderBy('position').execute(),
        db.selectFrom('sport_picks').selectAll().orderBy('list').orderBy('position').execute(),
      ]);
      const lists: Record<PickList, SportId[]> = {
        signUpCommon: [],
        checkInQuick: [],
      };
      for (const pick of picks) {
        lists[PickListName.parse(pick.list)].push(SportId.parse(pick.sport_id));
      }
      return {
        categories: categories.map((category) => ({
          id: category.id,
          names: {
            zhHans: category.name_zh_hans,
            en: category.name_en,
            zhHant: category.name_zh_hant,
          },
          sports: sports
            .filter((sport) => sport.category_id === category.id)
            .map((sport) => ({
              id: SportId.parse(sport.id),
              names: { zhHans: sport.name_zh_hans, en: sport.name_en, zhHant: sport.name_zh_hant },
              ...shortNamesOf(sport),
              icon: sport.icon,
              offered: sport.offered,
            })),
        })),
        picks: lists,
      } satisfies SportCatalog;
    },

    async has(id) {
      const row = await db
        .selectFrom('sports')
        .select('id')
        .where('id', '=', id)
        .executeTakeFirst();
      return row !== undefined;
    },

    async saveSport(sport, order) {
      const existing = await db
        .selectFrom('sports')
        .select('category_id')
        .where('id', '=', sport.id)
        .executeTakeFirst();
      const position = order.indexOf(sport.id) + 1;
      if (existing?.category_id === sport.category) {
        await db
          .updateTable('sports')
          .set(sportColumns(sport))
          .where('id', '=', sport.id)
          .execute();
        await renumber('sports', numbered(order));
        return;
      }
      // Make room in its new category first, then put it there.
      await renumber(
        'sports',
        numbered(order).filter(([id]) => id !== sport.id),
      );
      if (existing === undefined) {
        await db
          .insertInto('sports')
          .values({ id: sport.id, position, ...sportColumns(sport) })
          .execute();
        return;
      }
      await db
        .updateTable('sports')
        .set({ position, ...sportColumns(sport) })
        .where('id', '=', sport.id)
        .execute();
      // Close the gap it left.
      const left = await db
        .selectFrom('sports')
        .select('id')
        .where('category_id', '=', existing.category_id)
        .orderBy('position')
        .execute();
      await renumber('sports', numbered(left.map(({ id }) => id)));
    },

    async saveCategory(category, order) {
      const columns = {
        name_zh_hans: category.names.zhHans,
        name_en: category.names.en,
        name_zh_hant: category.names.zhHant,
      };
      const existing = await db
        .selectFrom('sport_categories')
        .select('id')
        .where('id', '=', category.id)
        .executeTakeFirst();
      if (existing !== undefined) {
        await db
          .updateTable('sport_categories')
          .set(columns)
          .where('id', '=', category.id)
          .execute();
        await renumber('sport_categories', numbered(order));
        return;
      }
      await renumber(
        'sport_categories',
        numbered(order).filter(([id]) => id !== category.id),
      );
      await db
        .insertInto('sport_categories')
        .values({ id: category.id, position: order.indexOf(category.id) + 1, ...columns })
        .execute();
    },

    async savePicks(list, sports) {
      // Rows that stay keep their row and only move, so the log shows what changed.
      await db
        .deleteFrom('sport_picks')
        .where('list', '=', list)
        .where('sport_id', 'not in', sports)
        .execute();
      const kept = new Set(
        (
          await db.selectFrom('sport_picks').select('sport_id').where('list', '=', list).execute()
        ).map(({ sport_id }) => sport_id),
      );
      const places = sports.map((id, index) => [id, index + 1] as const);
      const moved = places.filter(([id]) => kept.has(id));
      if (moved.length > 0) {
        const values = sql.join(moved.map(([id, position]) => sql`(${id}, ${position}::int)`));
        await sql`
          update public.sport_picks as pick set position = place.position
          from (values ${values}) as place (sport_id, position)
          where pick.list = ${list} and pick.sport_id = place.sport_id
            and pick.position <> place.position
        `.execute(db);
      }
      const added = places.filter(([id]) => !kept.has(id));
      if (added.length > 0) {
        await db
          .insertInto('sport_picks')
          .values(added.map(([sport_id, position]) => ({ list, position, sport_id })))
          .execute();
      }
    },
  };
}
