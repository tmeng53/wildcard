import { hasErrorCode } from '@wildcard/errors';
import { ReaderLanguage } from '@wildcard/language-model';
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

/** A profile's columns as `profile_events` logs them: the whole profile after each change. */
const LOGGED = [
  'member_id',
  'time_zone',
  'catchphrase',
  'nickname',
  'look',
  'jersey_number',
  'birthday',
  'equipped_title',
  'equipped_team_badge',
  'language',
] as const;

/** The profile store on Postgres (`supabase/migrations`). */
export function createPostgresProfileStore(db: Kysely<MemberTables>): ProfileStore {
  return {
    async find(member) {
      const row = await db
        .selectFrom('profiles')
        .select([
          'time_zone',
          'catchphrase',
          'nickname',
          'look',
          'jersey_number',
          sql<string | null>`birthday::text`.as('birthday'),
        ])
        .where('member_id', '=', member)
        .executeTakeFirst();
      return row === undefined
        ? undefined
        : Profile.parse({
            timeZone: row.time_zone,
            catchphrase: row.catchphrase,
            character: characterOf(row),
            jerseyNumber: row.jersey_number,
            birthday: row.birthday,
          });
    },

    async squadmates(members) {
      if (members.length === 0) return new Map();
      const rows = await db
        .selectFrom('profiles')
        .select([
          'member_id',
          'catchphrase',
          'nickname',
          'look',
          'jersey_number',
          'created_at',
          'equipped_title',
          'equipped_team_badge',
        ])
        .where('member_id', 'in', members)
        .execute();
      return new Map(
        rows.map((row) => [
          MemberId.parse(row.member_id),
          {
            catchphrase: row.catchphrase,
            character: characterOf(row),
            jerseyNumber: row.jersey_number,
            joinedAt: new Date(row.created_at),
            equippedTitle: row.equipped_title,
            equippedTeamBadge: row.equipped_team_badge,
          },
        ]),
      );
    },

    async wear(member, worn) {
      // One statement, like a save: the change and its log entry together, neither when it is
      // the one worn already. Wearing one takes the other off.
      const title = worn?.title ?? null;
      const teamBadge = worn?.teamBadge ?? null;
      await db
        .with('saved', (cte) =>
          cte
            .updateTable('profiles')
            .set({ equipped_title: title, equipped_team_badge: teamBadge })
            .where('member_id', '=', member)
            .where(
              sql<boolean>`(equipped_title, equipped_team_badge) is distinct from (${title}::text, ${teamBadge}::text)`,
            )
            .returning(LOGGED),
        )
        .insertInto('profile_events')
        .columns(LOGGED)
        .expression((eb) => eb.selectFrom('saved').select(LOGGED))
        .execute();
      const row = await db
        .selectFrom('profiles')
        .select('member_id')
        .where('member_id', '=', member)
        .executeTakeFirst();
      return row !== undefined;
    },

    async saveBirthday(member, birthday) {
      // One statement, like a save: the change and its log entry together, neither when it is
      // the birthday saved already.
      await db
        .with('saved', (cte) =>
          cte
            .updateTable('profiles')
            .set({ birthday })
            .where('member_id', '=', member)
            .where(sql<boolean>`birthday is distinct from ${birthday}::date`)
            .returning(LOGGED),
        )
        .insertInto('profile_events')
        .columns(LOGGED)
        .expression((eb) => eb.selectFrom('saved').select(LOGGED))
        .execute();
      const row = await db
        .selectFrom('profiles')
        .select('member_id')
        .where('member_id', '=', member)
        .executeTakeFirst();
      return row !== undefined;
    },

    async saveLanguage(member, language) {
      // One statement, like a save: the change and its log entry together, neither when it is
      // the language saved already.
      await db
        .with('saved', (cte) =>
          cte
            .updateTable('profiles')
            .set({ language })
            .where('member_id', '=', member)
            .where('language', '<>', language)
            .returning(LOGGED),
        )
        .insertInto('profile_events')
        .columns(LOGGED)
        .expression((eb) => eb.selectFrom('saved').select(LOGGED))
        .execute();
      const row = await db
        .selectFrom('profiles')
        .select('member_id')
        .where('member_id', '=', member)
        .executeTakeFirst();
      return row !== undefined;
    },

    async languages(members) {
      if (members.length === 0) return new Map();
      const rows = await db
        .selectFrom('profiles')
        .select(['member_id', 'language'])
        .where('member_id', 'in', members)
        .execute();
      return new Map(
        rows.map((row) => [MemberId.parse(row.member_id), ReaderLanguage.parse(row.language)]),
      );
    },

    async timeZones(members) {
      if (members.length === 0) return new Map();
      const rows = await db
        .selectFrom('profiles')
        .select(['member_id', 'time_zone'])
        .where('member_id', 'in', members)
        .execute();
      return new Map(rows.map((row) => [MemberId.parse(row.member_id), row.time_zone]));
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
      const kept = profile.jerseyNumber === undefined;
      const columns = {
        time_zone: profile.timeZone,
        catchphrase: profile.catchphrase,
        ...characterColumns(profile.character),
        ...(kept ? {} : { jersey_number: profile.jerseyNumber }),
      };
      // A number left out is compared with, and keeps, the one already saved.
      const number = kept ? sql`profiles.jersey_number` : sql`excluded.jersey_number`;
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
                    sql<boolean>`(profiles.time_zone, profiles.catchphrase, profiles.nickname, profiles.look, profiles.jersey_number)
                      is distinct from (excluded.time_zone, excluded.catchphrase, excluded.nickname, excluded.look, ${number})`,
                  ),
              )
              .returning(LOGGED),
          )
          .insertInto('profile_events')
          .columns(LOGGED)
          .expression((eb) => eb.selectFrom('saved').select(LOGGED))
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
