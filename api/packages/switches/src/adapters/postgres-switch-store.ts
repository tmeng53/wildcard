import { sql, type Kysely } from 'kysely';

import {
  MonthDay,
  SwitchId,
  SwitchMode,
  type Switch,
  type SwitchSetting,
} from '../domain/switches.js';
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
      return rows.map(switchOf);
    },

    async history() {
      // switch_events is the switches' own log: each row the full new value as it was set.
      const { rows } = await sql<{ at: Date | string; value: SwitchRow }>`
        select at, value from public.switch_events order by id
      `.execute(db);
      return rows.map((row): SwitchSetting => ({
        at: new Date(row.at),
        value: switchOf(row.value),
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

interface SwitchRow {
  id: string;
  label: string;
  mode: string;
  window_start: string | null;
  window_end: string | null;
}

function switchOf(row: SwitchRow): Switch {
  return {
    id: SwitchId.parse(row.id),
    label: row.label,
    mode: SwitchMode.parse(row.mode),
    ...(row.window_start === null || row.window_end === null
      ? {}
      : {
          window: { start: MonthDay.parse(row.window_start), end: MonthDay.parse(row.window_end) },
        }),
  };
}
