import { SportId } from '@wildcard/sport-ids';
import type { Kysely } from 'kysely';
import { z } from 'zod';

import { PICK_LISTS, type PickList, type SportCatalog } from '../domain/catalog.js';
import type { SportStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads, as generated from the migrations. */
export type SportTables = DB;

const PickListName = z.enum(PICK_LISTS);

/** The sports list on Postgres (`supabase/migrations`). */
export function createPostgresSportStore(db: Kysely<SportTables>): SportStore {
  return {
    async catalog() {
      const [categories, sports, picks] = await Promise.all([
        db.selectFrom('sport_categories').selectAll().orderBy('position').execute(),
        db.selectFrom('sports').selectAll().orderBy('category_id').orderBy('position').execute(),
        db.selectFrom('sport_picks').selectAll().orderBy('list').orderBy('position').execute(),
      ]);
      const lists: Record<PickList, SportId[]> = {
        signUpCommon: [],
        signUpMore: [],
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
  };
}
