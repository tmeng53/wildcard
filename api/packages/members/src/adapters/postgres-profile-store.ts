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
        .select(['time_zone', 'catchphrase'])
        .where('member_id', '=', member)
        .executeTakeFirst();
      return row === undefined
        ? undefined
        : Profile.parse({ timeZone: row.time_zone, catchphrase: row.catchphrase });
    },

    async catchphrases(members) {
      if (members.length === 0) return new Map();
      const rows = await db
        .selectFrom('profiles')
        .select(['member_id', 'catchphrase'])
        .where('member_id', 'in', members)
        .where('catchphrase', 'is not', null)
        .execute();
      return new Map(
        rows.flatMap(({ member_id, catchphrase }) =>
          catchphrase === null ? [] : [[MemberId.parse(member_id), catchphrase] as const],
        ),
      );
    },

    async joinedAt(member) {
      const row = await db
        .selectFrom('profiles')
        .select('created_at')
        .where('member_id', '=', member)
        .executeTakeFirst();
      return row === undefined ? undefined : new Date(row.created_at);
    },

    async save(member: MemberId, profile) {
      const columns = { time_zone: profile.timeZone, catchphrase: profile.catchphrase };
      try {
        await db
          .insertInto('profiles')
          .values({ member_id: member, ...columns })
          .onConflict((conflict) =>
            conflict.column('member_id').doUpdateSet({ ...columns, updated_at: sql`now()` }),
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
