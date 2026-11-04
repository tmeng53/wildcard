import type { Kysely } from 'kysely';

import { MonthDay, SwitchId, SwitchMode, type Switch } from '../domain/switches.js';
import type { SwitchStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads, as generated from the migrations. */
export type SwitchTables = DB;

/**
 * The switches on Postgres (`supabase/migrations`, `switches`). A change runs in the caller's
 * transaction when `db` is one; the table's triggers log each row that changes.
 */
export function createPostgresSwitchStore(db: Kysely<SwitchTables>): SwitchStore {
  return {
    async list() {
      const rows = await db.selectFrom('switches').selectAll().orderBy('id').execute();
      return rows.map((row): Switch => ({
        id: SwitchId.parse(row.id),
        label: row.label,
        mode: SwitchMode.parse(row.mode),
        ...(row.window_start === null || row.window_end === null
          ? {}
          : {
              window: {
                start: MonthDay.parse(row.window_start),
                end: MonthDay.parse(row.window_end),
              },
            }),
      }));
    },

    async put(of) {
      const columns = {
        label: of.label,
        mode: of.mode,
        window_start: of.window?.start ?? null,
        window_end: of.window?.end ?? null,
      };
      await db
        .insertInto('switches')
        .values({ id: of.id, ...columns })
        .onConflict((conflict) => conflict.column('id').doUpdateSet(columns))
        .execute();
    },
  };
}
