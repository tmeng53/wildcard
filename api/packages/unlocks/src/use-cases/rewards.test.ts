import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresRewardStore } from '../adapters/postgres-reward-store.js';
import { createPostgresUnlockStore } from '../adapters/postgres-unlock-store.js';
import type { DB } from '../adapters/tables.js';
import { EventName, RewardTriggerEdit } from '../domain/rewards.js';
import { MemberId, PieceId } from '../domain/unlocks.js';
import { RewardMissingError, RewardNotTeamGivenError } from '../errors.js';
import { createRewards } from './rewards.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<DB>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

const rewards = createRewards({
  store: createPostgresRewardStore(db),
  unlocks: createPostgresUnlockStore(db),
  clock: () => new Date('2026-11-09T12:00:00Z'),
});

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

const names = { 'zh-Hans': '点子王', 'zh-Hant': '點子王', en: 'Idea King' };

/** A badge, a voucher and a piece of their own, and an event no other test sets off. */
async function aSet() {
  const tag = randomUUID().slice(0, 8);
  const set = {
    badge: `idea-${tag}`,
    voucher: `week-${tag}`,
    piece: PieceId.parse(`thanks-${tag}`),
    event: EventName.parse(`test-${tag}`),
  };
  await rewards.putBadge({
    id: set.badge,
    names,
    glyph: 'lightbulb.fill',
    tone: '#F2B33D',
    offered: true,
  });
  await rewards.putVoucher({ id: set.voucher, premiumDays: 7, offered: true });
  for (const [kind, id] of [
    ['badge', set.badge],
    ['voucher', set.voucher],
    ['piece', set.piece],
  ] as const) {
    await rewards.putTrigger({ kind, id, way: 'event', events: [set.event], offered: true });
  }
  return set;
}

describe('rewards', () => {
  it('gives what an event’s triggers give, once an occurrence, and a piece once', async () => {
    const set = await aSet();
    const member = await newMember();
    const at = new Date('2026-11-09T10:00:00Z');
    const first = await rewards.happened({ member, event: set.event, id: 'f1', at });
    expect(first).toEqual(
      expect.arrayContaining([
        { kind: 'badge', id: set.badge },
        { kind: 'voucher', id: set.voucher },
        { kind: 'piece', id: set.piece },
      ]),
    );
    expect(first).toHaveLength(3);
    // The same occurrence again gives nothing; another gives the badge and voucher again.
    expect(await rewards.happened({ member, event: set.event, id: 'f1', at })).toEqual([]);
    const second = await rewards.happened({ member, event: set.event, id: 'f2', at });
    expect(second).toEqual(
      expect.arrayContaining([
        { kind: 'badge', id: set.badge },
        { kind: 'voucher', id: set.voucher },
      ]),
    );
    expect(second).toHaveLength(2);
    expect(await rewards.badgesOf(member)).toEqual([
      {
        badge: { id: set.badge, names, glyph: 'lightbulb.fill', tone: '#F2B33D', offered: true },
        times: 2,
        latestAt: at,
      },
    ]);
    expect(await rewards.teamPiecesOf(member)).toEqual([
      { piece: set.piece, givenAt: at, event: set.event },
    ]);
  });

  it('stops giving by a trigger no longer offered, and keeps what was given', async () => {
    const set = await aSet();
    const member = await newMember();
    const at = new Date('2026-11-09T10:00:00Z');
    await rewards.happened({ member, event: set.event, id: 'f1', at });
    await rewards.putTrigger({
      kind: 'badge',
      id: set.badge,
      way: 'event',
      events: [set.event],
      offered: false,
    });
    const later = await rewards.happened({ member, event: set.event, id: 'f2', at });
    expect(later).toEqual([{ kind: 'voucher', id: set.voucher }]);
    expect((await rewards.badgesOf(member)).map(({ times }) => times)).toEqual([1]);
    const listed = (await rewards.rewards()).find(
      ({ kind, id }) => kind === 'badge' && id === set.badge,
    );
    expect(listed?.triggers).toEqual([{ kind: 'event', offered: false, events: [set.event] }]);
  });

  it('gives by the team only what has an offered team trigger', async () => {
    const set = await aSet();
    const [member, admin] = [await newMember(), MemberId.parse(randomUUID())];
    await expect(
      rewards.give({ member, reward: { kind: 'badge', id: set.badge }, admin }),
    ).rejects.toThrow(RewardNotTeamGivenError);
    await rewards.putTrigger({ kind: 'badge', id: set.badge, way: 'team', offered: true });
    await rewards.putTrigger({ kind: 'piece', id: set.piece, way: 'team', offered: true });
    expect(await rewards.give({ member, reward: { kind: 'badge', id: set.badge }, admin })).toBe(
      true,
    );
    expect(await rewards.give({ member, reward: { kind: 'badge', id: set.badge }, admin })).toBe(
      true,
    );
    expect(await rewards.give({ member, reward: { kind: 'piece', id: set.piece }, admin })).toBe(
      true,
    );
    expect(await rewards.give({ member, reward: { kind: 'piece', id: set.piece }, admin })).toBe(
      false,
    );
    expect((await rewards.badgesOf(member)).map(({ times }) => times)).toEqual([2]);
    expect(await rewards.teamPiecesOf(member)).toEqual([
      { piece: set.piece, givenAt: new Date('2026-11-09T12:00:00Z') },
    ]);
  });

  it('names a badge or voucher only once it is in its catalog', async () => {
    await expect(
      rewards.putTrigger({ kind: 'voucher', id: 'no-such-voucher', way: 'team', offered: true }),
    ).rejects.toThrow(RewardMissingError);
  });

  it('asks for events with way event and none with way team', () => {
    expect(
      RewardTriggerEdit.safeParse({ kind: 'badge', id: 'bug-hunter', way: 'event', offered: true })
        .success,
    ).toBe(false);
    expect(
      RewardTriggerEdit.safeParse({
        kind: 'badge',
        id: 'bug-hunter',
        way: 'team',
        events: ['bug-adopted'],
        offered: true,
      }).success,
    ).toBe(false);
  });
});
