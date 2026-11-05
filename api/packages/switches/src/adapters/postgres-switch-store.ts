import type { Kysely } from 'kysely';

import { MonthDay, PLAIN_VIEW, SwitchId, SwitchMode, type Switch } from '../domain/switches.js';
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

    async viewOf(member) {
      const row = await db
        .selectFrom('switch_previews')
        .select(['previewer', 'day_offset'])
        .where('member_id', '=', member)
        .orderBy('id', 'desc')
        .limit(1)
        .executeTakeFirst();
      return row === undefined
        ? PLAIN_VIEW
        : { previewer: row.previewer, dayOffset: row.day_offset };
    },

    async setView({ member, view, by }) {
      const now = await this.viewOf(member);
      if (now.previewer === view.previewer && now.dayOffset === view.dayOffset) return;
      await db
        .insertInto('switch_previews')
        .values({
          member_id: member,
          previewer: view.previewer,
          day_offset: view.dayOffset,
          set_by: by,
        })
        .execute();
    },

    async previewers() {
      const rows = await db
        .selectFrom('switch_previews as p')
        .select(['p.member_id', 'p.previewer', 'p.day_offset'])
        .where((eb) =>
          eb.not(
            eb.exists(
              eb
                .selectFrom('switch_previews as newer')
                .select('newer.id')
                .whereRef('newer.member_id', '=', 'p.member_id')
                .whereRef('newer.id', '>', 'p.id'),
            ),
          ),
        )
        .orderBy('p.id')
        .execute();
      return rows
        .filter((row) => row.previewer)
        .map((row) => ({ member: row.member_id, dayOffset: row.day_offset }));
    },
  };
}
