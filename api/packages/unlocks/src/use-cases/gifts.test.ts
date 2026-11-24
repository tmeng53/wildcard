import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresGiftStore } from '../adapters/postgres-gift-store.js';
import type { DB } from '../adapters/tables.js';
import { CoachId, type CoachGift } from '../domain/gifts.js';
import { MemberId, PieceId } from '../domain/unlocks.js';
import {
  GiftAlreadyOwnedError,
  GiftNotGivenError,
  GiftPieceNotOfferedError,
  GiftWeeklyLimitError,
} from '../errors.js';
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

  const weekStart = new Date(Date.now() - 86_400_000);

  it('gives a member an offered piece with its line, tells it once, and keeps who gave it', async () => {
    const told: CoachGift[] = [];
    const gifts = giftsWith(told);
    const [member, piece, coach, squad] = [
      await newMember(),
      newPiece(),
      await aCoach(),
      randomUUID(),
    ];
    await gifts.putPiece({ id: piece, offered: true, description: '一条毛巾' });

    const gift = await gifts.give({
      member,
      piece,
      coach,
      squad,
      line: '练完擦汗',
      givenBy: 'coach',
      weekStart,
    });
    expect(gift).toMatchObject({ piece, coach, squad, line: '练完擦汗', givenBy: 'coach' });
    expect(gift.opened).toBeUndefined();
    expect(told).toStrictEqual([gift]);
    expect(await gifts.of(member)).toStrictEqual([gift]);
    expect((await gifts.pieces()).find(({ id }) => id === piece)).toStrictEqual({
      id: piece,
      offered: true,
      description: '一条毛巾',
    });
  });

  it('lets the coach give two a week, refuses a third and a piece the member already has', async () => {
    const gifts = giftsWith();
    const [member, coach] = [await newMember(), await aCoach()];
    const pieces = [newPiece(), newPiece(), newPiece(), newPiece()] as const;
    for (const id of pieces) await gifts.putPiece({ id, offered: true });
    const request = { member, coach, squad: randomUUID(), line: '给你', givenBy: 'coach' as const };
    await gifts.give({ ...request, piece: pieces[0], weekStart });
    await gifts.give({ ...request, piece: pieces[1], weekStart });

    await expect(gifts.give({ ...request, piece: pieces[2], weekStart })).rejects.toThrow(
      GiftWeeklyLimitError,
    );
    await expect(
      gifts.give({ ...request, piece: pieces[0], weekStart: new Date(Date.now() + 60_000) }),
    ).rejects.toThrow(GiftAlreadyOwnedError);
    // Next week, another piece is fine.
    const next = await gifts.give({
      ...request,
      piece: pieces[2],
      weekStart: new Date(Date.now() + 60_000),
    });
    expect(next).toMatchObject({ piece: pieces[2], givenBy: 'coach' });
    // An admin's gifts don't count toward the coach's two, and have no limit of their own.
    const [other, ...more] = [await newMember(), newPiece(), newPiece(), newPiece()];
    for (const id of more) await gifts.putPiece({ id, offered: true });
    const admin = {
      ...request,
      member: other,
      givenBy: 'admin' as const,
      admin: await newMember(),
    };
    for (const piece of more) await gifts.give({ ...admin, piece, weekStart });
    const fromCoach = await gifts.give({ ...request, member: other, piece: pieces[3], weekStart });
    expect(fromCoach).toMatchObject({ piece: pieces[3], givenBy: 'coach' });
    expect(await gifts.of(other)).toHaveLength(4);
  });

  it('refuses a piece the member already holds another way, as already theirs', async () => {
    const gifts = giftsWith();
    const [member, coach, piece] = [await newMember(), await aCoach(), newPiece()];
    await gifts.putPiece({ id: piece, offered: true });
    // Earned by training, as a piece both a rule and the pool name would be.
    await sql`insert into public.grants (member_id, reward_kind, reward_id, via, sports, after, check_in_id, at)
      values (${member}, 'piece', ${piece}, 'training', '{}', 1, ${randomUUID()}, now())`.execute(
      db,
    );
    await expect(
      gifts.give({
        member,
        coach,
        squad: randomUUID(),
        line: '给你',
        givenBy: 'coach',
        piece,
        weekStart,
      }),
    ).rejects.toThrow(GiftAlreadyOwnedError);
    expect(await gifts.of(member)).toStrictEqual([]);
  });

  it('gives only two of three coach gifts made at once in the same week', async () => {
    const gifts = giftsWith();
    const [member, coach, ...pieces] = [
      await newMember(),
      await aCoach(),
      newPiece(),
      newPiece(),
      newPiece(),
    ];
    for (const id of pieces) await gifts.putPiece({ id, offered: true });
    const request = { member, coach, squad: randomUUID(), line: '给你', givenBy: 'coach' as const };
    const all = await Promise.allSettled(
      pieces.map((piece) => gifts.give({ ...request, piece, weekStart })),
    );
    expect(all.filter(({ status }) => status === 'fulfilled')).toHaveLength(2);
    const refused = all.find((each) => each.status === 'rejected');
    expect(refused?.status === 'rejected' ? String(refused.reason) : '').toContain(
      'GiftWeeklyLimitError',
    );
    expect(await gifts.of(member)).toHaveLength(2);
  });

  it('keeps when a gift was opened and whether it was put on, once', async () => {
    const gifts = giftsWith();
    const [member, coach, piece] = [await newMember(), await aCoach(), newPiece()];
    await gifts.putPiece({ id: piece, offered: true });
    await expect(gifts.open({ member, piece, worn: true })).rejects.toThrow(GiftNotGivenError);
    await gifts.give({
      member,
      piece,
      coach,
      squad: randomUUID(),
      line: '给你',
      givenBy: 'coach',
      weekStart,
    });

    const opened = await gifts.open({ member, piece, worn: false });
    expect(opened.opened).toMatchObject({ worn: false });
    const again = await gifts.open({ member, piece, worn: true });
    expect(again.opened).toStrictEqual(opened.opened);
  });

  it('refuses a piece that is not in the pool or no longer offered', async () => {
    const gifts = giftsWith();
    const [member, coach, withdrawn] = [await newMember(), await aCoach(), newPiece()];
    await gifts.putPiece({ id: withdrawn, offered: false });
    for (const piece of [newPiece(), withdrawn]) {
      await expect(
        gifts.give({
          member,
          piece,
          coach,
          squad: randomUUID(),
          line: '给你',
          givenBy: 'coach',
          weekStart,
        }),
      ).rejects.toThrow(GiftPieceNotOfferedError);
    }
    expect(await gifts.of(member)).toStrictEqual([]);
  });
});
