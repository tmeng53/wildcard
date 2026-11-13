import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresPlaceRatingStore,
  type PlaceRatingTables,
} from '../adapters/postgres-place-rating-store.js';
import { MemberId, PlaceKey, Stars } from '../domain/place-rating.js';
import { createPlaceRatings } from './place-ratings.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<PlaceRatingTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

const ratings = createPlaceRatings({
  store: createPostgresPlaceRatingStore(db),
  clock: () => new Date(),
});

describe('place ratings', () => {
  it('keeps each member’s latest score, logging only changes', async () => {
    const [me, friend, other] = [await newMember(), await newMember(), await newMember()];
    const gym = PlaceKey.parse(`apple:I${randomUUID().slice(0, 8)}`);
    const park = PlaceKey.parse(`apple:I${randomUUID().slice(0, 8)}`);
    const rate = (member: MemberId, [place, stars]: readonly [PlaceKey, number]) =>
      ratings.rate({ member, place, stars: Stars.parse(stars) });

    expect(await rate(me, [gym, 2])).toBe('created');
    expect(await rate(me, [gym, 5])).toBe('created');
    expect(await rate(me, [gym, 5])).toBe('unchanged');
    expect(await rate(friend, [gym, 3])).toBe('created');
    expect(await rate(other, [gym, 1])).toBe('created');
    expect(await rate(friend, [park, 4])).toBe('created');

    const rows = await db
      .selectFrom('place_ratings')
      .select(['stars'])
      .where('member_id', '=', me)
      .orderBy('id')
      .execute();
    expect(rows.map(({ stars }) => stars)).toStrictEqual([2, 5]);

    expect(await ratings.of({ place: gym, members: [me, friend] })).toStrictEqual(
      new Map([
        [me, 5],
        [friend, 3],
      ]),
    );
    expect(await ratings.ofAll({ places: [gym, park], members: [friend] })).toStrictEqual(
      new Map([
        [gym, new Map([[friend, 3]])],
        [park, new Map([[friend, 4]])],
      ]),
    );
    expect(await ratings.of({ place: gym, members: [] })).toStrictEqual(new Map());
  });

  it('refuses to change or delete a score once logged', async () => {
    const me = await newMember();
    const place = PlaceKey.parse(`apple:I${randomUUID().slice(0, 8)}`);
    await ratings.rate({ member: me, place, stars: Stars.parse(4) });
    await expect(
      db.updateTable('place_ratings').set({ stars: 1 }).where('member_id', '=', me).execute(),
    ).rejects.toThrow();
    await expect(
      db.deleteFrom('place_ratings').where('member_id', '=', me).execute(),
    ).rejects.toThrow();
  });

  it('takes only Apple Maps’ keys and scores from 1 to 5', () => {
    expect(PlaceKey.safeParse('apple:I6FD7682FD36BB3BE').success).toBe(true);
    expect(PlaceKey.safeParse('I6FD7682FD36BB3BE').success).toBe(false);
    expect(PlaceKey.safeParse('apple:').success).toBe(false);
    expect([0, 1, 5, 6, 2.5].map((each) => Stars.safeParse(each).success)).toStrictEqual([
      false,
      true,
      true,
      false,
      false,
    ]);
  });
});
