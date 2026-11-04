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
import { createPostgresUnlockStore, createUnlocks } from '@wildcard/unlocks';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import {
  scenesOn,
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import {
  unusedWeeklyAwards,
  unusedWeekSummaryWords,
  unusedCoachHiring,
  unusedCoachActivity,
  ignoredNotices,
} from '../test-kit/weekly-awards.js';

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const sports = createSports({ store: createPostgresSportStore(db) });
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
  weeklyAwards: unusedWeeklyAwards,
  unlocks: createUnlocks({
    store: createPostgresUnlockStore(db),
    trainedSince: ({ member, since }) =>
      checkIns.trainedSince({ member: CheckInMember.parse(member), since }),
    sportListed: (id) => sports.isListed(id),
    switches: () => Promise.resolve(() => true),
  }),
  weekSummaryWords: unusedWeekSummaryWords,
  coachHiring: unusedCoachHiring,
  coachActivity: unusedCoachActivity,
  ...ignoredNotices,
  aiConsent: aiConsentOn(db),
  nudges: nudgesOn(db),
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
    body: { version: 1, name: 'squad' },
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

/** A 练了 the member posts to their squad, as the app does. */
async function train({
  member,
  squad,
  sport,
}: {
  readonly member: { readonly token: string };
  readonly squad: string;
  readonly sport: string;
}) {
  // Now: only check-ins made since the rules were added count, and a reset database adds them.
  const when = new Date();
  const body = {
    version: 1,
    day: when.toISOString().slice(0, 10),
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
  it('opens DEUCE CLUB after 3 网球类 练了, the racket on the first and each piece on its own', async () => {
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
    expect(locked).toHaveLength(52);
    expect(locked.find(({ id }) => id === 'powder-salmonhelmet')?.checkInsToGo).toBe(13);
    expect(locked.find(({ id }) => id === 'warmup-headphones')?.checkInsToGo).toBe(2);
    expect(locked.find(({ id }) => id === 'deuce-sweater')?.checkInsToGo).toBe(5);
    const first = await train({ member: me, squad, sport: 'tennis' });
    const run = await train({ member: me, squad, sport: 'run' });
    const squash = await train({ member: me, squad, sport: 'squash' });
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
        {
          kind: 'prop',
          id: 'racket',
          unlockedAt: first.at,
          reason: { sports: ['tennis', 'squash'], checkIns: 1 },
        },
        // The run counts for HALF MOON, any sport, but not for DEUCE CLUB.
        {
          kind: 'store',
          id: 'halfmoon',
          unlockedAt: squash.at,
          reason: { sports: [], checkIns: 3 },
        },
      ],
    });
    const third = await train({ member: me, squad, sport: 'pickleball' });
    const after = z
      .object({ unlocks: z.array(z.object({ id: z.string(), unlockedAt: z.string() })) })
      .parse((await unlocked(me)).body);
    expect(after.unlocks.map(({ id }) => id)).toStrictEqual([
      'racket',
      'halfmoon',
      // Both by the same check-in: props first.
      'pickleball',
      'deuce',
    ]);
    expect(after.unlocks.find(({ id }) => id === 'deuce')?.unlockedAt).toBe(third.at);

    expect(z.unknown().parse((await unlocked(me)).body)).toMatchObject(after);

    expect((await unlocked(friend)).body).toMatchObject({ version: 1, unlocks: [], pieces: [] });
    expect((await call({ method: 'GET', path: '/me/unlocks' })).status).toBe(401);
  });
});
