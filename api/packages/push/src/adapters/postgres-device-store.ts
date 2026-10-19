import { sql, type Kysely } from 'kysely';

import { DeviceToken, PushEnvironment, type Device } from '../domain/device.js';
import type { DeviceStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type PushTables = DB;

/** The device store on Postgres (`supabase/migrations`). */
export function createPostgresDeviceStore(db: Kysely<PushTables>): DeviceStore {
  return {
    async register(member, { token, environment }) {
      await db
        .insertInto('push_devices')
        .values({ token, member_id: member, environment })
        .onConflict((conflict) =>
          conflict
            .column('token')
            .doUpdateSet({ member_id: member, environment, registered_at: sql`now()` }),
        )
        .execute();
    },

    async unregister(member, token) {
      await db
        .deleteFrom('push_devices')
        .where('token', '=', token)
        .where('member_id', '=', member)
        .execute();
    },

    async devicesOf(members) {
      if (members.length === 0) return [];
      const rows = await db
        .selectFrom('push_devices')
        .select(['token', 'environment'])
        .where('member_id', 'in', members)
        .orderBy('token')
        .execute();
      return rows.map((row): Device => ({
        token: DeviceToken.parse(row.token),
        environment: PushEnvironment.parse(row.environment),
      }));
    },

    async remove(tokens) {
      if (tokens.length === 0) return;
      await db.deleteFrom('push_devices').where('token', 'in', tokens).execute();
    },
  };
}
