// GET /me/unlocks over the real check-ins, unlocks and database.
import { randomUUID } from 'node:crypto';

import {
  MemberId as CheckInMember,
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import {
  CoachId,
  MemberId,
  PieceId,
  createCoachGifts,
  createPostgresGiftStore,
  createPostgresRewardStore,
  createRewards,
  EventName,
  createPostgresUnlockStore,
  createUnlocks,
} from '@wildcard/unlocks';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import {
  scenesOn,
  switchesOn,
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  weatherOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import {
  unusedWeeklyAwards,
  unusedCoachHiring,
  unusedCoachActivity,
  unusedCoachLetters,
  ignoredNotices,
  unusedFeedback,
} from '../test-kit/weekly-awards.js';

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const sports = createSports({ store: createPostgresSportStore(db) });
const gifts = createCoachGifts({ store: createPostgresGiftStore(db) });
const rewards = createRewards({
  store: createPostgresRewardStore(db),
  unlocks: createPostgresUnlockStore(db),
  clock: () => new Date(),
});
const checkIns = createCheckIns({
  sports,
  store: createPostgresCheckInStore(db),
  membership: createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: () => Promise.resolve(true),
  }),
  reactions: createPostgresReactionStore(db),
  comments: createPostgresCommentStore(db),
  plans: createPostgresWeeklyPlanStore(db),
  photos,
  calendarOf: () => Promise.resolve(undefined),
  clock: () => new Date(),
});
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  accounts: createSupabaseAccounts({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  }),
  revokeAppleSignIn: undefined,
  catalog: catalogOn(db),
  publicRoutes: unlimitedPublicRoutes,
  photos,
  checkIns,
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  weeklyPlans: createWeeklyPlans({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: () => Promise.resolve(undefined),
    clock: () => new Date(),
  }),
  members: createMembers({ store: createPostgresProfileStore(db) }),
  push: pushOn(db),
  squads: createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: () => Promise.resolve(true),
  }),
  scenes: scenesOn(db),
  switches: switchesOn(db),
  weeklyAwards: unusedWeeklyAwards,
  unlocks: createUnlocks({
    store: createPostgresUnlockStore(db),
    trainedSince: ({ member, since }) =>
      checkIns.trainedSince({ member: CheckInMember.parse(member), since }),
    sportListed: (id) => sports.isListed(id),
    switches: () => Promise.resolve(() => true),
    switchListed: () => Promise.resolve(true),
  }),
  gifts,
  rewards,
  coachHiring: unusedCoachHiring,
  coachActivity: unusedCoachActivity,
  coachLetters: unusedCoachLetters,
  ...ignoredNotices,
  ...unusedFeedback,
  aiConsent: aiConsentOn(db),
  nudges: nudgesOn(db),
  weather: weatherOn(db),
  log: createLog(() => undefined),
  jobs: noJobs,
  admin: adminOn(),
});

async function call({
  method,
  path,
  token,
  body,
}: {
  readonly method: string;
  readonly path: string;
  readonly token?: string;
  readonly body?: unknown;
}) {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  const response = await app.request(path, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return {
    status: response.status,
    type: response.headers.get('content-type'),
    body: await response.json(),
  };
}

/** A squad the first member creates and the others join by its invite code, as the app does. */
async function squadOf(
  creator: { readonly token: string },
  ...others: readonly { readonly token: string }[]
) {
  const created = await call({
    method: 'PUT',
    path: `/squads/${randomUUID()}`,
    token: creator.token,
    body: { version: 1, name: 'squad', timeZone: 'America/New_York' },
  });
  const { id, inviteCode } = z.object({ id: z.uuid(), inviteCode: z.string() }).parse(created.body);
  for (const member of others) {
    const joined = await call({
      method: 'POST',
      path: `/squad-invites/${inviteCode}/accept`,
      token: member.token,
    });
    expect(joined.status).toBe(201);
  }
  return id;
}

/**
 * A 练了 the member posts to their squad, as the app does, for the day `daysAgo` days back (a
 * 补打卡 when more than 0), since a rule counts days, not posts.
 */
async function train({
  member,
  squad,
  sport,
  daysAgo,
}: {
  readonly member: { readonly token: string };
  readonly squad: string;
  readonly sport: string;
  readonly daysAgo: number;
}) {
  // Now: only check-ins made since the rules were added count, and a reset database adds them.
  const when = new Date();
  const body = {
    version: 1,
    day: new Date(when.getTime() - daysAgo * 86_400_000).toISOString().slice(0, 10),
    createdAt: when.toISOString(),
    audience: [squad],
    kind: 'trained',
    training: { sport },
  };
  const path = `/check-ins/${randomUUID()}`;
  const { status } = await call({ method: 'PUT', path, token: member.token, body });
  expect(status).toBe(201);
  return { at: when.toISOString() };
}

describe('GET /me/unlocks', () => {
  it('opens DEUCE CLUB after 3 网球类 练了 and each piece on its own, and no prop (they are everyone’s)', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me);
    const unlocked = async (member: { readonly token: string }) =>
      call({ method: 'GET', path: '/me/unlocks', token: member.token });

    const fresh = await unlocked(me);
    expect(fresh).toMatchObject({
      status: 200,
      type: 'application/json',
      body: { version: 1, unlocks: [], pieces: [] },
    });
    // Every piece with a rule starts locked, with how far it is.
    const locked = z
      .object({ lockedPieces: z.array(z.object({ id: z.string(), checkInsToGo: z.int() })) })
      .parse(fresh.body).lockedPieces;
    expect(locked).toHaveLength(57);
    expect(locked.find(({ id }) => id === 'powder-salmonhelmet')?.checkInsToGo).toBe(13);
    expect(locked.find(({ id }) => id === 'warmup-headphones')?.checkInsToGo).toBe(2);
    expect(locked.find(({ id }) => id === 'deuce-sweater')?.checkInsToGo).toBe(5);
    // The 商店街 as the server works it out, every switch on here: POWDER DAY is open with its
    // four starters out and the rest boxed; DEUCE CLUB, not yet earned, shows no piece.
    const shelf = z
      .object({
        shelf: z.object({
          stores: z.array(z.object({ id: z.string(), open: z.boolean() })),
          pieces: z.array(
            z.object({
              id: z.string(),
              storeId: z.string(),
              state: z.string(),
              checkInsToGo: z.int().optional(),
            }),
          ),
        }),
      })
      .parse(fresh.body).shelf;
    expect(shelf.stores.find(({ id }) => id === 'powder')).toStrictEqual({
      id: 'powder',
      open: true,
    });
    const powder = shelf.pieces.filter(({ storeId }) => storeId === 'powder');
    // POWDER DAY's starters are the member's while it is out, waiting to be claimed (领取).
    expect(powder.filter(({ state }) => state === 'owned')).toHaveLength(4);
    expect(powder.filter(({ state }) => state === 'locked')).toHaveLength(13);
    expect(powder.find(({ id }) => id === 'powder-tuna')).toMatchObject({
      state: 'locked',
      checkInsToGo: 1,
    });
    expect(shelf.pieces.some(({ storeId }) => storeId === 'deuce')).toBe(false);
    await train({ member: me, squad, sport: 'tennis', daysAgo: 4 });
    // A second 练了 on the same day counts nowhere: rules count days, not posts.
    await train({ member: me, squad, sport: 'tennis', daysAgo: 4 });
    const run = await train({ member: me, squad, sport: 'run', daysAgo: 3 });
    const squash = await train({ member: me, squad, sport: 'squash', daysAgo: 2 });
    const three = z
      .object({
        version: z.literal(1),
        unlocks: z.unknown(),
        pieces: z.unknown(),
        lockedPieces: z.array(z.object({ id: z.string(), checkInsToGo: z.int() })),
      })
      .parse((await unlocked(me)).body);
    expect(three.pieces).toStrictEqual([
      // WARM-UP's headphones open on the 2nd 练了 of any sport.
      {
        id: 'warmup-headphones',
        unlockedAt: run.at,
        reason: { sports: [], checkIns: 2 },
      },
    ]);
    expect(three.lockedPieces.find(({ id }) => id === 'deuce-sweater')?.checkInsToGo).toBe(3);
    expect(three.lockedPieces.find(({ id }) => id === 'lap-bib')?.checkInsToGo).toBe(4);
    expect(three.lockedPieces.some(({ id }) => id === 'warmup-headphones')).toBe(false);
    expect(three).toMatchObject({
      version: 1,
      unlocks: [
        // The run counts for HALF MOON, any sport, but not for DEUCE CLUB.
        {
          kind: 'store',
          id: 'halfmoon',
          unlockedAt: squash.at,
          reason: { sports: [], checkIns: 3 },
        },
      ],
    });
    const third = await train({ member: me, squad, sport: 'pickleball', daysAgo: 1 });
    const after = z
      .object({ unlocks: z.array(z.object({ id: z.string(), unlockedAt: z.string() })) })
      .parse((await unlocked(me)).body);
    expect(after.unlocks.map(({ id }) => id)).toStrictEqual(['halfmoon', 'deuce']);
    expect(after.unlocks.find(({ id }) => id === 'deuce')?.unlockedAt).toBe(third.at);

    expect(z.unknown().parse((await unlocked(me)).body)).toMatchObject(after);

    expect((await unlocked(friend)).body).toMatchObject({ version: 1, unlocks: [], pieces: [] });
    expect((await call({ method: 'GET', path: '/me/unlocks' })).status).toBe(401);
  });

  it('claims an unlocked piece into the wardrobe once, and only one the member unlocked', async () => {
    const me = await signUp();
    const squad = await squadOf(me);
    const mine = async () =>
      z
        .object({
          claimed: z.array(z.object({ id: z.string(), claimedAt: z.string() })),
          lockedPieces: z.array(z.object({ id: z.string(), sports: z.array(z.string()) })),
        })
        .parse((await call({ method: 'GET', path: '/me/unlocks', token: me.token })).body);
    const claim = (piece: string) =>
      call({ method: 'PUT', path: `/me/pieces/${piece}/claim`, token: me.token });

    const before = await mine();
    expect(before.claimed).toStrictEqual([]);
    // Each locked piece says which sports count, as its store's 「练这些运动解锁」 shows.
    expect(before.lockedPieces.find(({ id }) => id === 'lap-bib')?.sports).toStrictEqual([
      'run',
      'walk',
    ]);
    expect(before.lockedPieces.find(({ id }) => id === 'warmup-headphones')?.sports).toStrictEqual(
      [],
    );

    expect(await claim('warmup-headphones')).toMatchObject({
      status: 400,
      body: { reason: 'PIECE_NOT_UNLOCKED' },
    });
    await train({ member: me, squad, sport: 'run', daysAgo: 1 });
    // The second day of 练了 opens the headphones, and the claim counts it without a read first.
    await train({ member: me, squad, sport: 'yoga', daysAgo: 0 });
    const first = await claim('warmup-headphones');
    expect(first).toMatchObject({
      status: 200,
      body: { version: 1, claim: { id: 'warmup-headphones' } },
    });
    const again = await claim('warmup-headphones');
    expect(again.body).toStrictEqual(first.body);
    expect((await mine()).claimed).toStrictEqual([
      z.object({ claim: z.object({ id: z.string(), claimedAt: z.string() }) }).parse(first.body)
        .claim,
    ]);
    expect((await call({ method: 'PUT', path: '/me/pieces/warmup-headphones/claim' })).status).toBe(
      401,
    );
  });

  it('lists the pieces the team gave apart from the stores and the coach’s gifts', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const tag = randomUUID().slice(0, 8);
    const piece = PieceId.parse(`thanks-${tag}`);
    const event = EventName.parse(`test-${tag}`);
    await rewards.putTrigger({
      kind: 'piece',
      id: piece,
      way: 'event',
      events: [event],
      offered: true,
    });
    const at = new Date('2026-11-09T10:00:00Z');
    await rewards.happened({ member: MemberId.parse(me.userId), event, id: randomUUID(), at });
    const mine = await call({ method: 'GET', path: '/me/unlocks', token: me.token });
    expect(mine.body).toMatchObject({
      pieces: [],
      gifts: [],
      teamPieces: [{ id: piece, givenAt: at.toISOString(), event }],
    });
    const theirs = await call({ method: 'GET', path: '/me/unlocks', token: friend.token });
    expect(theirs.body).toMatchObject({ teamPieces: [] });
  });

  it('lists the pieces a coach gave apart from what training unlocked', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const piece = PieceId.parse(`gift-${randomUUID().slice(0, 8)}`);
    await gifts.putPiece({ id: piece, offered: true });
    const gift = await gifts.give({
      member: MemberId.parse(me.userId),
      piece,
      coach: CoachId.parse('xiaohun'),
      squad: randomUUID(),
      line: '天冷了，围上再出门。',
      givenBy: 'coach',
      weekStart: new Date(0),
    });
    const mine = await call({ method: 'GET', path: '/me/unlocks', token: me.token });
    expect(mine.body).toMatchObject({
      version: 1,
      unlocks: [],
      pieces: [],
      gifts: [
        {
          id: piece,
          coach: 'xiaohun',
          givenAt: gift.givenAt.toISOString(),
          line: '天冷了，围上再出门。',
        },
      ],
    });
    const theirs = await call({ method: 'GET', path: '/me/unlocks', token: friend.token });
    expect(theirs.body).toMatchObject({ gifts: [] });

    // 拆开: the first opening stands, and only the member it was given to can open it.
    const open = (token: string, worn: boolean) =>
      call({
        method: 'PUT',
        path: `/me/gifts/${piece}/open`,
        token,
        body: { version: 1, worn },
      });
    const opened = await open(me.token, true);
    expect(opened).toMatchObject({
      status: 200,
      body: { version: 1, gift: { id: piece, worn: true } },
    });
    expect(JSON.stringify(opened.body)).toContain('"openedAt"');
    expect((await open(me.token, false)).body).toStrictEqual(opened.body);
    expect(await open(friend.token, true)).toMatchObject({
      status: 404,
      body: { reason: 'GIFT_NOT_GIVEN' },
    });
  });
});
