import { hasErrorCode } from '@wildcard/errors';
import { sql, type Kysely } from 'kysely';
import { z } from 'zod';

import { Character, lookFields, MemberId, Profile } from '../domain/profile.js';
import type { ProfileStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type MemberTables = DB;

/** `profiles.look`: the look's fields beside the version of its stored shape. */
const StoredLook = z.discriminatedUnion('version', [
  z.strictObject({ version: z.literal(1), ...lookFields }),
]);

/** The columns a profile's character is kept in: both null, or both set. */
interface CharacterColumns {
  readonly nickname: string | null;
  readonly look: unknown;
}

function characterOf({ nickname, look }: CharacterColumns): Character | null {
  if (nickname === null || look === null) return null;
  const { persona, variants, colors } = StoredLook.parse(look);
  return Character.parse({ nickname, look: { persona, variants, colors } });
}

function characterColumns(character: Character | null) {
  return character === null
    ? { nickname: null, look: null }
    : {
        nickname: character.nickname,
        look: StoredLook.parse({ version: 1, ...character.look }),
      };
}

/** The profile store on Postgres (`supabase/migrations`). */
export function createPostgresProfileStore(db: Kysely<MemberTables>): ProfileStore {
  return {
    async find(member) {
      const row = await db
        .selectFrom('profiles')
        .select(['time_zone', 'catchphrase', 'nickname', 'look'])
        .where('member_id', '=', member)
        .executeTakeFirst();
      return row === undefined
        ? undefined
        : Profile.parse({
            timeZone: row.time_zone,
            catchphrase: row.catchphrase,
            character: characterOf(row),
          });
    },

    async squadmates(members) {
      if (members.length === 0) return new Map();
      const rows = await db
        .selectFrom('profiles')
        .select(['member_id', 'catchphrase', 'nickname', 'look'])
        .where('member_id', 'in', members)
        .execute();
      return new Map(
        rows.map((row) => [
          MemberId.parse(row.member_id),
          {
            catchphrase: row.catchphrase,
            character: characterOf(row),
          },
        ]),
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

    async pastLocalHour({ hour, now }) {
      // Postgres turns the moment into each member's wall-clock time with its own zone data,
      // the same data that checked the zone when it was saved.
      // The day before's hour comes from the same zone data, so it moves with a clock change.
      const local = sql`(${now}::timestamptz at time zone profiles.time_zone)`;
      const rows = await db
        .selectFrom('profiles')
        .select([
          'member_id',
          sql<string>`${local}::date::text`.as('day'),
          sql<Date>`((${local})::date - 1 + make_time(${hour}::int, 0, 0)) at time zone profiles.time_zone`.as(
            'hour_the_day_before',
          ),
        ])
        .where(sql<boolean>`extract(hour from ${local}) >= ${hour}`)
        .orderBy('member_id')
        .execute();
      return rows.map((row) => ({
        member: MemberId.parse(row.member_id),
        day: row.day,
        hourTheDayBefore: new Date(row.hour_the_day_before),
      }));
    },

    async save(member: MemberId, profile) {
      const columns = {
        time_zone: profile.timeZone,
        catchphrase: profile.catchphrase,
        ...characterColumns(profile.character),
      };
      try {
        // One statement: the profile and its log entry are saved together, and a save that
        // changes nothing writes neither.
        await db
          .with('saved', (cte) =>
            cte
              .insertInto('profiles')
              .values({ member_id: member, ...columns })
              .onConflict((conflict) =>
                conflict
                  .column('member_id')
                  .doUpdateSet(columns)
                  .where(
                    sql<boolean>`(profiles.time_zone, profiles.catchphrase, profiles.nickname, profiles.look)
                      is distinct from (excluded.time_zone, excluded.catchphrase, excluded.nickname, excluded.look)`,
                  ),
              )
              .returning(['member_id', 'time_zone', 'catchphrase', 'nickname', 'look']),
          )
          .insertInto('profile_events')
          .columns(['member_id', 'time_zone', 'catchphrase', 'nickname', 'look'])
          .expression((eb) =>
            eb
              .selectFrom('saved')
              .select(['member_id', 'time_zone', 'catchphrase', 'nickname', 'look']),
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
