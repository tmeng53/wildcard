import { hasErrorCode } from '@wildcard/errors';
import { sql, type Kysely, type Selectable } from 'kysely';
import { z } from 'zod';

import {
  CheckInId,
  LocalDay,
  MemberId,
  SquadId,
  entryFromStored,
  photosOf,
  storedPayload,
  type CheckInRecord,
} from '../domain/check-in.js';
import { PhotoPath, type PhotoRef } from '../domain/photos.js';
import type { CheckInStore, InsertOutcome } from '../ports.js';
import type { CheckIns, DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type CheckInTables = DB;

/** Which uniqueness rule a unique violation (23505) names. */
const UNIQUE_RULES: Record<string, 'id' | 'dailyDisclaimer' | 'photo' | undefined> = {
  check_ins_pkey: 'id',
  check_ins_one_disclaimer_a_day: 'dailyDisclaimer',
  // The path is the key, so a photo belongs to one check-in.
  check_in_photos_pkey: 'photo',
};

const Constraint = z.object({ constraint: z.string() });

/** The check-in store on Postgres (`supabase/migrations`). */
export function createPostgresCheckInStore(db: Kysely<CheckInTables>): CheckInStore {
  // A `date` read as text: node-postgres would turn it into a Date at local midnight.
  const checkInColumns = [
    'check_ins.id',
    'check_ins.member_id',
    sql<string>`check_ins.day::text`.as('day'),
    'check_ins.created_at',
    'check_ins.kind',
    'check_ins.payload',
  ] as const;

  type Row = Pick<Selectable<CheckIns>, 'id' | 'member_id' | 'created_at' | 'kind' | 'payload'> & {
    day: string;
  };

  /** Rows with their audiences and photos, in the rows' order. */
  async function withAudiences(rows: readonly Row[]): Promise<CheckInRecord[]> {
    if (rows.length === 0) return [];
    const ids = rows.map((row) => row.id);
    const [audienceRows, photoRows] = await Promise.all([
      db
        .selectFrom('check_in_squads')
        .select(['check_in_id', 'squad_id'])
        .where('check_in_id', 'in', ids)
        .orderBy('check_in_id')
        .orderBy('position')
        .execute(),
      db
        .selectFrom('check_in_photos')
        .select(['check_in_id', 'path'])
        .where('check_in_id', 'in', ids)
        .orderBy('check_in_id')
        .orderBy('position')
        .execute(),
    ]);
    const audiences = new Map<string, SquadId[]>();
    for (const { check_in_id, squad_id } of audienceRows) {
      audiences.set(check_in_id, [...(audiences.get(check_in_id) ?? []), SquadId.parse(squad_id)]);
    }
    const photos = new Map<string, PhotoRef[]>();
    for (const { check_in_id, path } of photoRows) {
      photos.set(check_in_id, [
        ...(photos.get(check_in_id) ?? []),
        { path: PhotoPath.parse(path) },
      ]);
    }
    return rows.map((row) => ({
      id: CheckInId.parse(row.id),
      member: MemberId.parse(row.member_id),
      day: LocalDay.parse(row.day),
      createdAt: row.created_at,
      audience: audiences.get(row.id) ?? [],
      ...entryFromStored({ ...row, photos: photos.get(row.id) ?? [] }),
    }));
  }

  return {
    async find(id) {
      const rows = await db
        .selectFrom('check_ins')
        .select(checkInColumns)
        .where('id', '=', id)
        .execute();
      const [found] = await withAudiences(rows);
      return found;
    },

    async insert(checkIn): Promise<InsertOutcome> {
      try {
        await db.transaction().execute(async (trx) => {
          await trx
            .insertInto('check_ins')
            .values({
              id: checkIn.id,
              member_id: checkIn.member,
              day: checkIn.day,
              created_at: checkIn.createdAt,
              kind: checkIn.kind,
              payload: JSON.stringify(storedPayload(checkIn)),
            })
            .execute();
          await trx
            .insertInto('check_in_squads')
            .values(
              checkIn.audience.map((squad, index) => ({
                check_in_id: checkIn.id,
                squad_id: squad,
                position: index + 1,
              })),
            )
            .execute();
          const photos = photosOf(checkIn);
          if (photos.length > 0) {
            await trx
              .insertInto('check_in_photos')
              .values(
                photos.map(({ path }, index) => ({
                  path,
                  check_in_id: checkIn.id,
                  position: index + 1,
                })),
              )
              .execute();
          }
        });
        return { saved: true };
      } catch (error) {
        const constraint = Constraint.safeParse(error).data?.constraint;
        const taken = constraint === undefined ? undefined : UNIQUE_RULES[constraint];
        if (hasErrorCode(error, '23505') && taken !== undefined) return { saved: false, taken };
        throw error;
      }
    },

    async countTrainedDays(member) {
      const { days } = await db
        .selectFrom('check_ins')
        .select(sql<string>`count(distinct day)`.as('days'))
        .where('member_id', '=', member)
        .where('kind', '=', 'trained')
        .executeTakeFirstOrThrow();
      return Number(days);
    },

    async listForSquad({ squad, members, from, to }) {
      if (members.length === 0) return [];
      const rows = await db
        .selectFrom('check_ins')
        .innerJoin('check_in_squads', (join) =>
          join
            .onRef('check_in_squads.check_in_id', '=', 'check_ins.id')
            .on('check_in_squads.squad_id', '=', squad),
        )
        .select(checkInColumns)
        .where('check_ins.member_id', 'in', members)
        .where('check_ins.day', '>=', from)
        .where('check_ins.day', '<=', to)
        .orderBy('check_ins.day', 'desc')
        .orderBy('check_ins.created_at', 'desc')
        .orderBy('check_ins.id')
        .execute();
      return withAudiences(rows);
    },

    async squadsCheckedInto({ from, to, before }) {
      const rows = await db
        .selectFrom('check_in_squads')
        .innerJoin('check_ins', 'check_ins.id', 'check_in_squads.check_in_id')
        .select('check_in_squads.squad_id')
        .distinct()
        .where('check_ins.day', '>=', from)
        .where('check_ins.day', '<=', to)
        .where('check_ins.created_at', '<', before)
        .orderBy('check_in_squads.squad_id')
        .execute();
      return rows.map((row) => SquadId.parse(row.squad_id));
    },

    async listForMember({ member, from, to }) {
      const rows = await db
        .selectFrom('check_ins')
        .select(checkInColumns)
        .where('member_id', '=', member)
        .where('day', '>=', from)
        .where('day', '<=', to)
        .orderBy('day', 'desc')
        .orderBy('created_at', 'desc')
        .orderBy('id')
        .execute();
      return withAudiences(rows);
    },
  };
}
