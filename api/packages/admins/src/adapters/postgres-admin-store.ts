import type { Kysely } from 'kysely';

import { AdminAction, AdminId } from '../domain/admin-action.js';
import type { AdminStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type AdminTables = DB;

/** The admin store on Postgres (`supabase/migrations`). */
export function createPostgresAdminStore(db: Kysely<AdminTables>): AdminStore {
  return {
    isAdmin: async (member) => {
      const row = await db
        .selectFrom('admins')
        .select('member_id')
        .where('member_id', '=', member)
        .executeTakeFirst();
      return row !== undefined;
    },
    list: async () => {
      const rows = await db.selectFrom('admins').select('member_id').execute();
      return rows.map(({ member_id }) => AdminId.parse(member_id));
    },
    log: async ({ admin, at, action }) => {
      await db
        .insertInto('admin_actions')
        .values({ admin_id: admin, at, action: JSON.stringify(action) })
        .execute();
    },
    listLog: async ({ admin, limit }) => {
      const rows = await db
        .selectFrom('admin_actions')
        .select(['admin_id', 'at', 'action'])
        .where('admin_id', '=', admin)
        .orderBy('at', 'desc')
        .orderBy('id', 'desc')
        .limit(limit)
        .execute();
      return rows.map((row) => ({
        admin: AdminId.parse(row.admin_id),
        at: row.at,
        action: AdminAction.parse(row.action),
      }));
    },
  };
}
