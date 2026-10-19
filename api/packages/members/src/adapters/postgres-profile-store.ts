import { hasErrorCode } from '@wildcard/errors';
import { sql, type Kysely } from 'kysely';

import { MemberId, Profile } from '../domain/profile.js';
import type { ProfileStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type MemberTables = DB;

/** The profile store on Postgres (`supabase/migrations`). */
export function createPostgresProfileStore(db: Kysely<MemberTables>): ProfileStore {
  return {
    async find(member) {
      const row = await db
        .selectFrom('profiles')
        .select('time_zone')
        .where('member_id', '=', member)
        .executeTakeFirst();
      return row === undefined ? undefined : Profile.parse({ timeZone: row.time_zone });
    },

    async joinedAt(member) {
      const row = await db
        .selectFrom('profiles')
        .select('created_at')
        .where('member_id', '=', member)
        .executeTakeFirst();
      return row === undefined ? undefined : new Date(row.created_at);
    },

    async pastLocalHour({ hour, now }) {
      // Postgres turns the moment into each member's wall-clock time with its own zone data,
      // the same data that checked the zone when it was saved.
      const local = sql`(${now}::timestamptz at time zone profiles.time_zone)`;
      const rows = await db
        .selectFrom('profiles')
        .select(['member_id', sql<string>`${local}::date::text`.as('day')])
        .where(sql<boolean>`extract(hour from ${local}) >= ${hour}`)
        .orderBy('member_id')
        .execute();
      return rows.map(({ member_id, day }) => ({ member: MemberId.parse(member_id), day }));
    },

    async save(member: MemberId, profile) {
      try {
        await db
          .insertInto('profiles')
          .values({ member_id: member, time_zone: profile.timeZone })
          .onConflict((conflict) =>
            conflict
              .column('member_id')
              .doUpdateSet({ time_zone: profile.timeZone, updated_at: sql`now()` }),
          )
          .execute();
        return true;
      } catch (error) {
        // invalid_parameter_value from the trigger that checks Postgres knows the zone.
        if (hasErrorCode(error, '22023')) return false;
        throw error;
      }
    },
  };
}
