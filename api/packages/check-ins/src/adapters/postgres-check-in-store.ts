import { PlaceKey } from '@wildcard/place-ids';
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
  workoutOf,
  type CheckInRecord,
} from '../domain/check-in.js';
import { storedWorkout, workoutFromStored, workoutView, type Workout } from '../domain/workout.js';
import { PhotoPath, type PhotoRef } from '../domain/photos.js';
import { SportKey } from '../domain/sports.js';
import type { CheckInTotals } from '../domain/totals.js';
import type { CheckInStore, InsertOutcome, UpdateOutcome } from '../ports.js';
import type { CheckIns, DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type CheckInTables = DB;

/** Which uniqueness rule a unique violation (23505) names. */
const UNIQUE_RULES: Record<string, 'id' | 'photo' | 'workout' | undefined> = {
  check_ins_pkey: 'id',
  // The path is the key, so a photo belongs to one check-in.
  check_in_photos_pkey: 'photo',
  // A member posts each workout once.
  check_in_workouts_once: 'workout',
};

const Constraint = z.object({ constraint: z.string() });

/** The photo rows of a check-in, the cover at position 1. */
function photoRows(checkIn: CheckInRecord) {
  return photosOf(checkIn).map(({ path, size }, index) => ({
    path,
    check_in_id: checkIn.id,
    position: index + 1,
    width: size?.width ?? null,
    height: size?.height ?? null,
  }));
}

/** The `check_in_workouts` row of a check-in, if it has a workout. */
function workoutRow(checkIn: CheckInRecord) {
  const workout = workoutOf(checkIn);
  if (workout === undefined) return undefined;
  return { check_in_id: checkIn.id, member_id: checkIn.member, ...storedWorkout(workout) };
}

/** A `check_in_events` row: the whole entry as saved, the photos in order, and any workout. */
function eventRow(checkIn: CheckInRecord, kind: 'posted' | 'edited') {
  const workout = workoutOf(checkIn);
  return {
    check_in_id: checkIn.id,
    member_id: checkIn.member,
    kind,
    entry: JSON.stringify({
      version: 1,
      payload: storedPayload(checkIn),
      photos: photosOf(checkIn).map(({ path, size }) =>
        size === undefined ? { path } : { path, width: size.width, height: size.height },
      ),
      ...(workout === undefined ? {} : { workout: workoutView(workout) }),
    }),
  };
}

/** The check-in store on Postgres (`supabase/migrations`). */
export function createPostgresCheckInStore(db: Kysely<CheckInTables>): CheckInStore {
  // A `date` read as text: node-postgres would turn it into a Date at local midnight.
  const checkInColumns = [
    'check_ins.id',
    'check_ins.member_id',
    sql<string>`check_ins.day::text`.as('day'),
    sql<string>`check_ins.posted_day::text`.as('posted_day'),
    'check_ins.created_at',
    'check_ins.kind',
    'check_ins.payload',
    'check_ins.in_feed',
  ] as const;

  type Row = Pick<
    Selectable<CheckIns>,
    'id' | 'member_id' | 'created_at' | 'kind' | 'payload' | 'in_feed'
  > & {
    day: string;
    posted_day: string;
  };

  /** Rows with their audiences and photos, in the rows' order. */
  async function withAudiences(rows: readonly Row[]): Promise<CheckInRecord[]> {
    if (rows.length === 0) return [];
    const ids = rows.map((row) => row.id);
    const [audienceRows, photoRows, workoutRows] = await Promise.all([
      db
        .selectFrom('check_in_squads')
        .select(['check_in_id', 'squad_id'])
        .where('check_in_id', 'in', ids)
        .orderBy('check_in_id')
        .orderBy('position')
        .execute(),
      db
        .selectFrom('check_in_photos')
        .select(['check_in_id', 'path', 'width', 'height'])
        .where('check_in_id', 'in', ids)
        .orderBy('check_in_id')
        .orderBy('position')
        .execute(),
      db.selectFrom('check_in_workouts').selectAll().where('check_in_id', 'in', ids).execute(),
    ]);
    const workouts = new Map<string, Workout>(
      workoutRows.map((row) => [row.check_in_id, workoutFromStored(row)] as const),
    );
    const audiences = new Map<string, SquadId[]>();
    for (const { check_in_id, squad_id } of audienceRows) {
      audiences.set(check_in_id, [...(audiences.get(check_in_id) ?? []), SquadId.parse(squad_id)]);
    }
    const photos = new Map<string, PhotoRef[]>();
    for (const { check_in_id, path, width, height } of photoRows) {
      // The key is left out, never undefined, so a retry compares equal to the saved check-in.
      const photo: PhotoRef =
        width === null || height === null
          ? { path: PhotoPath.parse(path) }
          : { path: PhotoPath.parse(path), size: { width, height } };
      photos.set(check_in_id, [...(photos.get(check_in_id) ?? []), photo]);
    }
    return rows.map((row) => ({
      id: CheckInId.parse(row.id),
      member: MemberId.parse(row.member_id),
      day: LocalDay.parse(row.day),
      postedDay: LocalDay.parse(row.posted_day),
      createdAt: row.created_at,
      audience: audiences.get(row.id) ?? [],
      inFeed: row.in_feed,
      ...entryFromStored({
        ...row,
        photos: photos.get(row.id) ?? [],
        workout: workouts.get(row.id),
      }),
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
              posted_day: checkIn.postedDay ?? checkIn.day,
              created_at: checkIn.createdAt,
              kind: checkIn.kind,
              payload: JSON.stringify(storedPayload(checkIn)),
              in_feed: checkIn.inFeed,
            })
            .execute();
          if (checkIn.audience.length > 0) {
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
          }
          const photos = photoRows(checkIn);
          if (photos.length > 0) await trx.insertInto('check_in_photos').values(photos).execute();
          const workout = workoutRow(checkIn);
          if (workout !== undefined)
            await trx.insertInto('check_in_workouts').values(workout).execute();
          await trx.insertInto('check_in_events').values(eventRow(checkIn, 'posted')).execute();
        });
        return { saved: true };
      } catch (error) {
        const constraint = Constraint.safeParse(error).data?.constraint;
        const taken = constraint === undefined ? undefined : UNIQUE_RULES[constraint];
        if (hasErrorCode(error, '23505') && taken !== undefined) return { saved: false, taken };
        throw error;
      }
    },

    async update(checkIn): Promise<UpdateOutcome> {
      try {
        await db.transaction().execute(async (trx) => {
          await trx
            .updateTable('check_ins')
            .set({ payload: JSON.stringify(storedPayload(checkIn)) })
            .where('id', '=', checkIn.id)
            .execute();
          await trx.deleteFrom('check_in_photos').where('check_in_id', '=', checkIn.id).execute();
          const photos = photoRows(checkIn);
          if (photos.length > 0) await trx.insertInto('check_in_photos').values(photos).execute();
          await trx.deleteFrom('check_in_workouts').where('check_in_id', '=', checkIn.id).execute();
          const workout = workoutRow(checkIn);
          if (workout !== undefined)
            await trx.insertInto('check_in_workouts').values(workout).execute();
          await trx.insertInto('check_in_events').values(eventRow(checkIn, 'edited')).execute();
        });
        return { saved: true };
      } catch (error) {
        const constraint = Constraint.safeParse(error).data?.constraint;
        const taken = constraint === undefined ? undefined : UNIQUE_RULES[constraint];
        if (hasErrorCode(error, '23505') && (taken === 'photo' || taken === 'workout')) {
          return { saved: false, taken };
        }
        throw error;
      }
    },

    async remove(id) {
      // Its audience, photo rows, workout, reactions, comments, coach wakes and log go with it.
      await db.deleteFrom('check_ins').where('id', '=', id).execute();
    },

    async photoHistory(id) {
      const rows = await db
        .selectFrom('check_in_events')
        .select(sql<string>`jsonb_array_elements(entry -> 'photos') ->> 'path'`.as('path'))
        .where('check_in_id', '=', id)
        .execute();
      return [...new Set(rows.map(({ path }) => path))].map((path) => PhotoPath.parse(path));
    },

    totals: (member) => totalsOf(db, { member }),

    totalsSharedTo: ({ member, squad }) => totalsOf(db, { member, squad }),

    async streakDays({ member, squad }) {
      const rows = await db
        .selectFrom('check_ins')
        .select([sql<string>`day::text`.as('day'), 'kind'])
        .distinct()
        .where('member_id', '=', member)
        .where('kind', 'in', ['trained', 'healthyMeal', 'cheatMeal', 'disclaimer'])
        .where(sharedTo(squad))
        .orderBy('day')
        .execute();
      const daysOf = (kinds: readonly string[]) => [
        ...new Set(rows.filter((row) => kinds.includes(row.kind)).map((row) => row.day)),
      ];
      return {
        trained: daysOf(['trained']),
        meals: daysOf(['healthyMeal', 'cheatMeal']),
        leave: daysOf(['disclaimer']),
      };
    },

    async trainedSince({ member, since }) {
      const rows = await db
        .selectFrom('check_ins')
        .select([
          'id',
          sql<string>`payload ->> 'sport'`.as('sport'),
          sql<string>`day::text`.as('day'),
          'created_at',
        ])
        .where('member_id', '=', member)
        .where('kind', '=', 'trained')
        .where('created_at', '>=', since)
        .orderBy('created_at')
        .orderBy('id')
        .execute();
      return rows.map((row) => ({
        id: CheckInId.parse(row.id),
        sport: SportKey.parse(row.sport),
        day: row.day,
        madeAt: new Date(row.created_at),
      }));
    },

    async listForSquad({ squad, members, from, to, by = 'day' }) {
      if (members.length === 0) return [];
      const dayColumn = by === 'postedDay' ? 'check_ins.posted_day' : 'check_ins.day';
      const rows = await db
        .selectFrom('check_ins')
        .innerJoin('check_in_squads', (join) =>
          join
            .onRef('check_in_squads.check_in_id', '=', 'check_ins.id')
            .on('check_in_squads.squad_id', '=', squad),
        )
        .select(checkInColumns)
        .where('check_ins.member_id', 'in', members)
        .where(dayColumn, '>=', from)
        .where(dayColumn, '<=', to)
        .orderBy(dayColumn, 'desc')
        .orderBy('check_ins.created_at', 'desc')
        .orderBy('check_ins.id')
        .execute();
      return withAudiences(rows);
    },

    async placedForSquad({ squad, limit }) {
      const rows = await db
        .selectFrom('check_ins')
        .innerJoin('check_in_squads', (join) =>
          join
            .onRef('check_in_squads.check_in_id', '=', 'check_ins.id')
            .on('check_in_squads.squad_id', '=', squad),
        )
        .select(checkInColumns)
        .where('check_ins.in_feed', '=', true)
        .where(sql<boolean>`check_ins.payload ? 'place'`)
        .orderBy('check_ins.created_at', 'desc')
        .orderBy('check_ins.id')
        .limit(limit)
        .execute();
      return withAudiences(rows);
    },

    async placesTrainedBefore({ squad, members, keys, before }) {
      if (members.length === 0 || keys.length === 0) return new Set();
      // The key as `@wildcard/place-ids` makes it: the squad's own place first, else Maps' id.
      const key = sql<string>`case
        when check_ins.payload->'place' ? 'squadPlaceId'
          then 'squad:' || lower(check_ins.payload->'place'->>'squadPlaceId')
        else 'apple:' || (check_ins.payload->'place'->>'appleId')
      end`;
      const rows = await db
        .selectFrom('check_ins')
        .innerJoin('check_in_squads', (join) =>
          join
            .onRef('check_in_squads.check_in_id', '=', 'check_ins.id')
            .on('check_in_squads.squad_id', '=', squad),
        )
        .select(key.as('key'))
        .distinct()
        .where('check_ins.member_id', 'in', members)
        .where('check_ins.kind', '=', 'trained')
        .where('check_ins.in_feed', '=', true)
        .where('check_ins.day', '<', before)
        .where(key, 'in', keys)
        .execute();
      return new Set(rows.map((row) => PlaceKey.parse(row.key)));
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

    async trainingsForMember({ member, from, to }) {
      const rows = await db
        .selectFrom('check_ins')
        .select([
          'id',
          sql<string>`check_ins.day::text`.as('day'),
          sql<string>`payload ->> 'sport'`.as('sport'),
          sql<string | null>`payload ->> 'customSport'`.as('customSport'),
          sql<string | null>`payload ->> 'minutes'`.as('minutes'),
        ])
        .where('member_id', '=', member)
        .where('kind', '=', 'trained')
        .where('day', '>=', from)
        .where('day', '<=', to)
        .orderBy('day')
        .orderBy('created_at')
        .orderBy('id')
        .execute();
      return rows.map((row) => ({
        id: CheckInId.parse(row.id),
        day: row.day,
        sport: SportKey.parse(row.sport),
        ...(row.customSport === null ? {} : { customSport: row.customSport }),
        ...(row.minutes === null ? {} : { minutes: Number(row.minutes) }),
      }));
    },

    async recordRows({ member, squad, mates }) {
      const trainingRows = await db
        .selectFrom('check_ins')
        .select([
          'member_id',
          sql<string>`check_ins.day::text`.as('day'),
          sql<string>`check_ins.posted_day::text`.as('posted_day'),
          'created_at',
          sql<string>`payload ->> 'sport'`.as('sport'),
          sql<string | null>`payload ->> 'customSport'`.as('customSport'),
          sql<string | null>`payload ->> 'minutes'`.as('minutes'),
          sql<string | null>`payload ->> 'startTime'`.as('startTime'),
          sql<Date | null>`(
            select started_at from check_in_workouts
            where check_in_workouts.check_in_id = check_ins.id
          )`.as('workoutStartedAt'),
        ])
        .select(
          sql<boolean>`exists (
            select 1 from check_in_squads
            where check_in_squads.check_in_id = check_ins.id
              and check_in_squads.squad_id = ${squad ?? null}
          )`.as('in_squad'),
        )
        .where('kind', '=', 'trained')
        .where((eb) =>
          squad === undefined || mates.length === 0
            ? eb('member_id', '=', member)
            : eb.or([
                eb('member_id', '=', member),
                eb.and([
                  eb('member_id', 'in', mates),
                  eb.exists(
                    eb
                      .selectFrom('check_in_squads')
                      .select('check_in_squads.check_in_id')
                      .whereRef('check_in_squads.check_in_id', '=', 'check_ins.id')
                      .where('check_in_squads.squad_id', '=', squad),
                  ),
                ]),
              ]),
        )
        .orderBy('created_at')
        .orderBy('id')
        .execute();
      const meals = await db
        .selectFrom('check_ins')
        .select(sql<string>`check_ins.day::text`.as('day'))
        .distinct()
        .where('member_id', '=', member)
        .where('kind', '=', 'healthyMeal')
        .execute();
      const leave = await db
        .selectFrom('check_ins')
        .select(sql<string>`check_ins.day::text`.as('day'))
        .distinct()
        .where('member_id', '=', member)
        .where('kind', '=', 'disclaimer')
        .execute();
      const reactionCounts = async (author: 'member' | 'mates') => {
        if (mates.length === 0) return new Map<MemberId, number>();
        const rows = await db
          .selectFrom('check_in_reactions')
          .innerJoin('check_ins', 'check_ins.id', 'check_in_reactions.check_in_id')
          .select([
            author === 'member'
              ? 'check_in_reactions.member_id as mate'
              : 'check_ins.member_id as mate',
            sql<string>`count(*)`.as('count'),
          ])
          .where(
            author === 'member' ? 'check_ins.member_id' : 'check_in_reactions.member_id',
            '=',
            member,
          )
          .where(
            author === 'member' ? 'check_in_reactions.member_id' : 'check_ins.member_id',
            'in',
            mates,
          )
          .groupBy(author === 'member' ? 'check_in_reactions.member_id' : 'check_ins.member_id')
          .execute();
        return new Map(rows.map((row) => [MemberId.parse(row.mate), Number(row.count)]));
      };
      return {
        trainings: trainingRows.map((row) => ({
          member: MemberId.parse(row.member_id),
          day: row.day,
          postedDay: row.posted_day,
          madeAt: new Date(row.created_at),
          sport: SportKey.parse(row.sport),
          ...(row.customSport === null ? {} : { customSport: row.customSport }),
          ...(row.minutes === null ? {} : { minutes: Number(row.minutes) }),
          ...(row.startTime === null ? {} : { startTime: row.startTime }),
          ...(row.workoutStartedAt === null
            ? {}
            : { workoutStartedAt: new Date(row.workoutStartedAt) }),
          inSquad: row.in_squad,
        })),
        healthyMealDays: meals.map((row) => row.day),
        leaveDays: leave.map((row) => row.day),
        received: await reactionCounts('member'),
        given: await reactionCounts('mates'),
      };
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

    async pageForMember({ member, kind, after, limit }) {
      let query = db.selectFrom('check_ins').select(checkInColumns).where('member_id', '=', member);
      if (kind !== undefined) query = query.where('kind', '=', kind);
      if (after !== undefined) {
        query = query.where(
          sql<boolean>`(check_ins.day, check_ins.created_at, check_ins.id) < (${after.day}::date, ${after.createdAt}, ${after.id}::uuid)`,
        );
      }
      const rows = await query
        .orderBy('day', 'desc')
        .orderBy('created_at', 'desc')
        .orderBy('id', 'desc')
        .limit(limit)
        .execute();
      return withAudiences(rows);
    },

    async countForMember(member) {
      const { count } = await db
        .selectFrom('check_ins')
        .select(sql<string>`count(*)`.as('count'))
        .where('member_id', '=', member)
        .executeTakeFirstOrThrow();
      return Number(count);
    },
  };
}

/** Only what reached `squad`, when asked for a squad's view: a 仅自己可见 post never counts. */
const sharedTo = (squad: SquadId | undefined) =>
  squad === undefined
    ? sql<boolean>`true`
    : sql<boolean>`exists (select 1 from check_in_squads where check_in_squads.check_in_id = check_ins.id and check_in_squads.squad_id = ${squad})`;

/** The counts of everything `member` checked in, or of only what they shared to `squad`. */
async function totalsOf(
  db: Kysely<CheckInTables>,
  { member, squad }: { readonly member: MemberId; readonly squad?: SquadId },
): Promise<CheckInTotals> {
  const shared = sharedTo(squad);
  const counts = await db
    .selectFrom('check_ins')
    .select([
      sql<string>`count(distinct day) filter (where kind = 'trained')`.as('trainedDays'),
      sql<string>`count(*) filter (where kind = 'healthyMeal')`.as('healthyMeals'),
      sql<string>`count(*) filter (where kind = 'cheatMeal')`.as('cheatMeals'),
      // A 休息 (`restDay`) is a planned rest, not a 请假条.
      sql<string>`count(*) filter (where kind = 'disclaimer' and payload -> 'restDay' is null)`.as(
        'disclaimers',
      ),
    ])
    .where('member_id', '=', member)
    .where(shared)
    .executeTakeFirstOrThrow();
  const top = await db
    .selectFrom('check_ins')
    .select([
      sql<string>`payload ->> 'sport'`.as('sport'),
      sql<string | null>`payload ->> 'customSport'`.as('customSport'),
      sql<string>`count(*)`.as('checkIns'),
    ])
    .where('member_id', '=', member)
    .where(shared)
    .where('kind', '=', 'trained')
    .groupBy([sql`payload ->> 'sport'`, sql`payload ->> 'customSport'`])
    .orderBy(sql`count(*)`, 'desc')
    .orderBy(sql`max(created_at)`, 'desc')
    .limit(1)
    .executeTakeFirst();
  return {
    trainedDays: Number(counts.trainedDays),
    healthyMeals: Number(counts.healthyMeals),
    cheatMeals: Number(counts.cheatMeals),
    disclaimers: Number(counts.disclaimers),
    ...(top === undefined
      ? {}
      : {
          topSport: {
            sport: SportKey.parse(top.sport),
            ...(top.customSport === null ? {} : { customSport: top.customSport }),
            checkIns: Number(top.checkIns),
          },
        }),
  };
}
