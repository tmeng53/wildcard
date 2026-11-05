import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresGiftStore } from '../adapters/postgres-gift-store.js';
import type { DB } from '../adapters/tables.js';
import { CoachId, type CoachGift } from '../domain/gifts.js';
import { MemberId, PieceId } from '../domain/unlocks.js';
import { GiftPieceNotOfferedError } from '../errors.js';
import { createCoachGifts } from './gifts.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<DB>({
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

const newPiece = () => PieceId.parse(`gift-${randomUUID().slice(0, 8)}`);

async function aCoach() {
  const row = await sql<{ id: string }>`select id from public.coaches order by id limit 1`.execute(
    db,
  );
  return CoachId.parse(row.rows[0]?.id);
}

function giftsWith(told: CoachGift[] = []) {
  return createCoachGifts({
    store: createPostgresGiftStore(db),
    gifted: (_member, gift) => {
      told.push(gift);
      return Promise.resolve();
    },
  });
}

describe('coach gifts', () => {
  it('offers only the pool’s offered pieces, and keeps a withdrawn one listed for admins', async () => {
    const gifts = giftsWith();
    const [kept, withdrawn] = [newPiece(), newPiece()];
    await gifts.putPiece({ id: kept, offered: true });
    await gifts.putPiece({ id: withdrawn, offered: true });
    const pool = await gifts.putPiece({ id: withdrawn, offered: false });
    expect(pool).toEqual(
      expect.arrayContaining([
        { id: kept, offered: true },
        { id: withdrawn, offered: false },
      ]),
    );
    const offered = (await gifts.offered()).map(({ id }) => id);
    expect(offered).toContain(kept);
    expect(offered).not.toContain(withdrawn);
  });

  it('gives a member an offered piece once, tells it once, and keeps who gave it', async () => {
    const told: CoachGift[] = [];
    const gifts = giftsWith(told);
    const [member, piece, coach, squad] = [
      await newMember(),
      newPiece(),
      await aCoach(),
      randomUUID(),
    ];
    await gifts.putPiece({ id: piece, offered: true });

    const first = await gifts.give({ member, piece, coach, squad });
    expect(first).toMatchObject({ fresh: true, gift: { piece, coach, squad } });
    const again = await gifts.give({ member, piece, coach, squad: randomUUID() });
    expect(again).toStrictEqual({ fresh: false, gift: first.gift });

    expect(told).toStrictEqual([first.gift]);
    expect(await gifts.of(member)).toStrictEqual([first.gift]);
  });

  it('refuses a piece that is not in the pool or no longer offered', async () => {
    const gifts = giftsWith();
    const [member, coach, withdrawn] = [await newMember(), await aCoach(), newPiece()];
    await gifts.putPiece({ id: withdrawn, offered: false });
    for (const piece of [newPiece(), withdrawn]) {
      await expect(gifts.give({ member, piece, coach, squad: randomUUID() })).rejects.toThrow(
        GiftPieceNotOfferedError,
      );
    }
    expect(await gifts.of(member)).toStrictEqual([]);
  });
});
