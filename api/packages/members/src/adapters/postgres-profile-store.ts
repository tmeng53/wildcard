import { hasErrorCode } from '@wildcard/errors';
import { sql, type Kysely } from 'kysely';

import { MemberId, Profile, TimeZone } from '../domain/profile.js';
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

    async timeZonesOf(members) {
      if (members.length === 0) return new Map();
      const rows = await db
        .selectFrom('profiles')
        .select(['member_id', 'time_zone'])
        .where('member_id', 'in', members)
        .execute();
      return new Map(
        rows.map((row) => [MemberId.parse(row.member_id), TimeZone.parse(row.time_zone)]),
      );
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
