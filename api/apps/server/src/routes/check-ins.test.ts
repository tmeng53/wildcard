import { randomUUID } from 'node:crypto';

import {
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
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { PhotoPath } from '../ports.js';
import { createLog } from '../log.js';
import {
  scenesOn,
  switchesOn,
  adminOn,
  aiConsentOn,
  alsoJoinedEarlier,
  config,
  noJobs,
  nudgesOn,
  placesOn,
  savedPlacesOn,
  weatherOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import {
  unusedWeeklyAwards,
  unusedUnlocks,
  unusedGifts,
  noRewards,
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
/** The check-ins the coaches were asked to look at, as the route asks. */
const looked: { readonly checkIn: string; readonly squads: readonly string[] }[] = [];
const places = placesOn(db);
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
  checkIns: createCheckIns({
    sports: createSports({ store: createPostgresSportStore(db) }),
    squadPlaceOf: (input) => places.squadPlaces.isPlaceOf(input),
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
  }),
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
  unlocks: unusedUnlocks,
  gifts: unusedGifts,
  rewards: noRewards,
  coachHiring: unusedCoachHiring,
  coachActivity: unusedCoachActivity,
  coachLetters: unusedCoachLetters,
  ...ignoredNotices,
  ...unusedFeedback,
  aiConsent: aiConsentOn(db),
  nudges: nudgesOn(db),
  ...places,
  savedPlaces: savedPlacesOn(db),
  weather: weatherOn(db),
  log: createLog(() => undefined),
  jobs: {
    ...noJobs,
    coach: {
      run: () => Promise.reject(new Error('unused')),
      preview: () => Promise.reject(new Error('unused')),
      welcome: () => Promise.resolve(),
      answer: () => Promise.reject(new Error('unused')),
      checkedIn: (asked) => {
        looked.push(asked);
        return Promise.resolve();
      },
    },
  },
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
    // A 204 has no body.
    body: response.status === 204 ? undefined : await response.json(),
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

/** A photo the member uploads through `POST /photo-uploads`, as the app does; its path. */
async function uploadPhoto(token: string, bytes: string) {
  const { body } = await call({ method: 'POST', path: '/photo-uploads', token });
  const { path, uploadUrl } = z.object({ path: z.string(), uploadUrl: z.url() }).parse(body);
  const uploaded = await fetch(uploadUrl, {
    method: 'PUT',
    headers: { 'content-type': 'image/jpeg' },
    body: bytes,
  });
  expect(uploaded.ok).toBe(true);
  return path;
}

/** Today as a UTC date, and a moment a minute ago: always inside the time window. */
function todayAndNow() {
  const now = new Date(Date.now() - 60_000);
  return { day: now.toISOString().slice(0, 10), createdAt: now.toISOString() };
}

describe('PUT /check-ins/{id}', () => {
  it('saves a check-in, and answers a retry with the saved one', async () => {
    const me = await signUp();
    const squad = await squadOf(me);
    const id = randomUUID();
    const { day, createdAt } = todayAndNow();
    const body = {
      version: 1,
      day,
      createdAt,
      audience: [squad],
      kind: 'trained',
      training: { sport: 'custom', customSport: ' 飞盘 ', caption: '累但爽' },
    };
    const expected = {
      version: 1,
      id,
      member: me.userId,
      day,
      postedDay: day,
      createdAt,
      audience: [squad],
      inFeed: true,
      kind: 'trained',
      training: { sport: 'custom', customSport: '飞盘', caption: '累但爽' },
    };
    expect(
      await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body }),
    ).toStrictEqual({
      status: 201,
      type: 'application/json',
      body: expected,
    });
    expect(
      await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body }),
    ).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: expected,
    });
    // The squads' coaches look at it once, while the first save's request runs; not on a retry.
    expect(looked.filter(({ checkIn }) => checkIn === id)).toStrictEqual([
      { checkIn: id, squads: [squad] },
    ]);
  });

  it('answers each refusal as a problem with its reason', async () => {
    const me = await signUp();
    const squad = await squadOf(me);
    const { day, createdAt } = todayAndNow();
    const disclaimer = (text: string) => ({
      version: 1,
      day,
      createdAt,
      audience: [squad],
      kind: 'disclaimer',
      disclaimer: { text },
    });
    const put = async (id: string, body: unknown) => {
      const {
        status,
        type,
        body: problem,
      } = await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body });
      return [status, type, z.object({ reason: z.string() }).parse(problem).reason];
    };
    const first = randomUUID();
    expect(
      (
        await call({
          method: 'PUT',
          path: `/check-ins/${first}`,
          token: me.token,
          body: disclaimer('加班'),
        })
      ).status,
    ).toBe(201);
    expect(await put(first, disclaimer('下雨'))).toStrictEqual([
      409,
      'application/problem+json',
      'CHECK_IN_ID_CONFLICT',
    ]);
    // Any number of 请假条 a day.
    expect(
      (
        await call({
          method: 'PUT',
          path: `/check-ins/${randomUUID()}`,
          token: me.token,
          body: disclaimer('下雨'),
        })
      ).status,
    ).toBe(201);
    expect(
      await put(randomUUID(), { ...disclaimer('累'), audience: [randomUUID()] }),
    ).toStrictEqual([403, 'application/problem+json', 'SQUAD_NOT_JOINED']);
    expect(
      await put(randomUUID(), {
        ...disclaimer('累'),
        createdAt: '2020-01-01T00:00:00.000Z',
        day: '2020-01-01',
      }),
    ).toStrictEqual([400, 'application/problem+json', 'CHECK_IN_TOO_OLD']);
    const trained = (sport: string) => ({
      version: 1,
      day,
      createdAt,
      audience: [squad],
      kind: 'trained',
      training: { sport },
    });
    expect(await put(randomUUID(), trained('quidditch'))).toStrictEqual([
      400,
      'application/problem+json',
      'SPORT_NOT_LISTED',
    ]);
    expect(await put(randomUUID(), trained('not a sport id'))).toStrictEqual([
      400,
      'application/problem+json',
      'REQUEST_INVALID',
    ]);
    expect(await put(randomUUID(), { ...disclaimer('累'), calories: 300 })).toStrictEqual([
      400,
      'application/problem+json',
      'REQUEST_INVALID',
    ]);
    expect(await put('not-a-uuid', disclaimer('累'))).toStrictEqual([
      400,
      'application/problem+json',
      'REQUEST_INVALID',
    ]);
    const malformed = await app.request(`/check-ins/${randomUUID()}`, {
      method: 'PUT',
      headers: { authorization: `Bearer ${me.token}`, 'content-type': 'application/json' },
      body: 'nope',
    });
    expect([
      malformed.status,
      malformed.headers.get('content-type'),
      z.object({ reason: z.string() }).parse(await malformed.json()).reason,
    ]).toStrictEqual([400, 'application/problem+json', 'REQUEST_INVALID']);
    for (const contentType of ['text/plain', undefined]) {
      const headers: Record<string, string> = { authorization: `Bearer ${me.token}` };
      if (contentType !== undefined) headers['content-type'] = contentType;
      // Bytes, since a string body would get `text/plain` from `Request` when no type is given.
      const body = new TextEncoder().encode(JSON.stringify(disclaimer('累')));
      const sent = new Request('http://localhost/', { method: 'PUT', headers, body });
      expect(sent.headers.get('content-type')).toBe(contentType ?? null);
      const notJson = await app.request(`/check-ins/${randomUUID()}`, {
        method: 'PUT',
        headers,
        body,
      });
      expect([
        notJson.status,
        notJson.headers.get('content-type'),
        z.object({ reason: z.string() }).parse(await notJson.json()).reason,
      ]).toStrictEqual([415, 'application/problem+json', 'MEDIA_TYPE_UNSUPPORTED']);
    }
  });

  it('asks a caller with no token to sign in', async () => {
    const { status, body } = await call({
      method: 'PUT',
      path: `/check-ins/${randomUUID()}`,
      body: {},
    });
    expect([status, z.object({ reason: z.string() }).parse(body).reason]).toStrictEqual([
      401,
      'AUTH_TOKEN_MISSING',
    ]);
  });
});

describe('GET /squads/{squadId}/check-ins and /me/check-ins', () => {
  it('lists a squad’s check-ins for its members, and a member’s own', async () => {
    const [me, friend, stranger] = [await signUp(), await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const friendsOther = await squadOf(await signUp());
    await alsoJoinedEarlier(db, { squad: friendsOther, member: friend.userId });
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const body = {
      version: 1,
      day,
      createdAt,
      audience: [friendsOther, squad],
      kind: 'healthyMeal',
      meal: { caption: '番茄炒蛋' },
    };
    expect(
      (await call({ method: 'PUT', path: `/check-ins/${id}`, token: friend.token, body })).status,
    ).toBe(201);
    const saved = {
      version: 1,
      id,
      member: friend.userId,
      day,
      postedDay: day,
      createdAt,
      inFeed: true,
      kind: 'healthyMeal',
      meal: { caption: '番茄炒蛋' },
    };
    const range = `from=${day}&to=${day}`;
    const reacted = await call({
      method: 'PUT',
      path: `/check-ins/${id}/reactions/mine`,
      token: me.token,
      body: { version: 1, emoji: '🤤' },
    });
    expect(reacted.status).toBe(201);
    const { reactedAt } = z.object({ reactedAt: z.string() }).parse(reacted.body);

    // The feed: each post with its reactions.
    expect(
      await call({ method: 'GET', path: `/squads/${squad}/check-ins?${range}`, token: me.token }),
    ).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: {
        version: 1,
        posts: [
          {
            checkIn: { ...saved, audience: [squad] },
            reactions: [{ member: me.userId, emoji: '🤤', reactedAt }],
            comments: [],
          },
        ],
      },
    });
    expect(
      await call({ method: 'GET', path: `/me/check-ins?${range}`, token: friend.token }),
    ).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: { version: 1, checkIns: [{ ...saved, audience: [friendsOther, squad] }] },
    });
    expect(
      await call({ method: 'GET', path: `/me/check-ins?${range}`, token: me.token }),
    ).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: { version: 1, checkIns: [] },
    });

    const refused = await call({
      method: 'GET',
      path: `/squads/${squad}/check-ins?${range}`,
      token: stranger.token,
    });
    expect([
      refused.status,
      z.object({ reason: z.string() }).parse(refused.body).reason,
    ]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
  });

  it('records a check-in with 发布到动态 off for the squad, out of its 动态', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const body = {
      version: 1,
      day,
      createdAt,
      audience: [squad],
      inFeed: false,
      kind: 'trained',
      training: { sport: 'run', caption: '只给自己看' },
    };
    const saved = await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body });
    expect([
      saved.status,
      z.object({ inFeed: z.boolean() }).parse(saved.body).inFeed,
    ]).toStrictEqual([201, false]);
    // The coach answers posts only.
    expect(looked.filter(({ checkIn }) => checkIn === id)).toStrictEqual([]);
    const range = `from=${day}&to=${day}`;
    for (const viewer of [me, friend]) {
      expect(
        await call({
          method: 'GET',
          path: `/squads/${squad}/check-ins?${range}`,
          token: viewer.token,
        }),
      ).toStrictEqual({ status: 200, type: 'application/json', body: { version: 1, posts: [] } });
    }
    expect((await call({ method: 'GET', path: `/check-ins/${id}`, token: me.token })).status).toBe(
      200,
    );
    expect(
      (await call({ method: 'GET', path: `/check-ins/${id}`, token: friend.token })).status,
    ).toBe(404);
    expect(
      (
        await call({
          method: 'PUT',
          path: `/check-ins/${id}/reactions/mine`,
          token: friend.token,
          body: { version: 1, emoji: '🤤' },
        })
      ).status,
    ).toBe(404);
    // No post to talk under, for its author either, so nobody is told and the coach never hears.
    expect(
      (
        await call({
          method: 'PUT',
          path: `/check-ins/${id}/comments/${randomUUID()}`,
          token: me.token,
          body: { version: 1, text: `@${friend.userId}`, mentions: [friend.userId] },
        })
      ).status,
    ).toBe(404);
    // An edit keeps it out of 动态.
    const edited = await call({
      method: 'PATCH',
      path: `/check-ins/${id}`,
      token: me.token,
      body: { version: 1, kind: 'trained', training: { sport: 'run', caption: '改一下' } },
    });
    expect([
      edited.status,
      z.object({ inFeed: z.boolean() }).parse(edited.body).inFeed,
    ]).toStrictEqual([200, false]);
  });

  it('takes an older build’s 仅自己可见 as sent to the squad, off its 动态', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const body = {
      version: 1,
      day,
      createdAt,
      audience: [],
      kind: 'disclaimer',
      disclaimer: { text: '累' },
    };
    const posted = {
      version: 1,
      id,
      member: me.userId,
      day,
      postedDay: day,
      createdAt,
      audience: [squad],
      inFeed: false,
      kind: 'disclaimer',
      disclaimer: { text: '累' },
    };
    expect(
      await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body }),
    ).toStrictEqual({ status: 201, type: 'application/json', body: posted });
    // A retry from that build is the same check-in.
    expect(
      (await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body })).status,
    ).toBe(200);
    const range = `from=${day}&to=${day}`;
    expect(
      await call({ method: 'GET', path: `/me/check-ins?${range}`, token: me.token }),
    ).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: { version: 1, checkIns: [posted] },
    });
    expect(
      await call({
        method: 'GET',
        path: `/squads/${squad}/check-ins?${range}`,
        token: friend.token,
      }),
    ).toStrictEqual({ status: 200, type: 'application/json', body: { version: 1, posts: [] } });
  });

  it('refuses a range of more than 31 days, or one that runs backwards', async () => {
    const me = await signUp();
    const reasons = await Promise.all(
      ['from=2026-10-01&to=2026-11-01', 'from=2026-10-18&to=2026-10-17', 'from=2026-10-18'].map(
        async (query) => {
          const { status, body } = await call({
            method: 'GET',
            path: `/me/check-ins?${query}`,
            token: me.token,
          });
          return [status, z.object({ reason: z.string() }).parse(body).reason];
        },
      ),
    );
    expect(reasons).toStrictEqual([
      [400, 'REQUEST_INVALID'],
      [400, 'REQUEST_INVALID'],
      [400, 'REQUEST_INVALID'],
    ]);
    expect(
      (
        await call({
          method: 'GET',
          path: '/me/check-ins?from=2026-10-01&to=2026-10-31',
          token: me.token,
        })
      ).status,
    ).toBe(200);
  });
});

describe('GET /me/posts', () => {
  it('pages through the member’s own check-ins with their reactions and counts', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const earlier = new Date(Date.now() - 60 * 60_000);
    const later = new Date(Date.now() - 60_000);
    const put = async (when: Date, fields: Record<string, unknown>) => {
      const id = randomUUID();
      const body = {
        version: 1,
        // The member has no time zone, so any day near the moment is taken.
        day: when.toISOString().slice(0, 10),
        createdAt: when.toISOString(),
        audience: [squad],
        ...fields,
      };
      expect(
        (await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body })).status,
      ).toBe(201);
      return { ...body, id, member: me.userId, postedDay: body.day, inFeed: true };
    };
    const run = await put(earlier, { kind: 'trained', training: { sport: 'run', minutes: 30 } });
    const meal = await put(later, { kind: 'cheatMeal', meal: { caption: '火锅' } });
    const reacted = await call({
      method: 'PUT',
      path: `/check-ins/${run.id}/reactions/mine`,
      token: friend.token,
      body: { version: 1, emoji: '💪' },
    });
    const { reactedAt } = z.object({ reactedAt: z.string() }).parse(reacted.body);

    const first = await call({ method: 'GET', path: '/me/posts?limit=1', token: me.token });
    const Page = z.object({ next: z.string().optional() });
    const { next } = Page.parse(first.body);
    expect(first).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: {
        version: 1,
        posts: [{ checkIn: meal, reactions: [], comments: [] }],
        next,
        counts: { posts: 2, reactions: 1 },
      },
    });
    expect(
      await call({
        method: 'GET',
        path: `/me/posts?limit=1&after=${String(next)}`,
        token: me.token,
      }),
    ).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: {
        version: 1,
        posts: [
          {
            checkIn: run,
            reactions: [{ member: friend.userId, emoji: '💪', reactedAt }],
            comments: [],
          },
        ],
      },
    });
    const trained = await call({ method: 'GET', path: '/me/posts?kind=trained', token: me.token });
    expect(z.object({ posts: z.array(z.unknown()) }).parse(trained.body).posts).toHaveLength(1);
    // Someone else's history holds none of them.
    expect(
      (await call({ method: 'GET', path: '/me/posts', token: friend.token })).body,
    ).toStrictEqual({
      version: 1,
      posts: [],
      counts: { posts: 0, reactions: 0 },
    });
  });

  it('refuses a kind, limit or `after` it doesn’t know, and a caller who isn’t signed in', async () => {
    const me = await signUp();
    const reasons = await Promise.all(
      ['kind=nap', 'limit=0', 'limit=61', 'after=nope'].map(async (query) => {
        const { status, body } = await call({
          method: 'GET',
          path: `/me/posts?${query}`,
          token: me.token,
        });
        return [status, z.object({ reason: z.string() }).parse(body).reason];
      }),
    );
    expect(reasons).toStrictEqual(Array(4).fill([400, 'REQUEST_INVALID']));
    expect((await call({ method: 'GET', path: '/me/posts' })).status).toBe(401);
  });
});

describe('GET /me/trainings', () => {
  it('lists the member’s 练了 by day with sport and minutes, wherever they went', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me);
    const today = new Date().toISOString().slice(0, 10);
    const yesterday = new Date(Date.parse(today) - 24 * 60 * 60_000).toISOString().slice(0, 10);
    // Made a few minutes ago, in order, so the day's 练了 list the earliest made first.
    const put = async (
      made: { minutesAgo: number; day: string; audience: string[] },
      fields: object,
    ) => {
      const id = randomUUID();
      const createdAt = new Date(Date.now() - made.minutesAgo * 60_000).toISOString();
      const body = { version: 1, day: made.day, createdAt, audience: made.audience, ...fields };
      const { status } = await call({
        method: 'PUT',
        path: `/check-ins/${id}`,
        token: me.token,
        body,
      });
      expect(status).toBe(201);
      return id;
    };
    const run = await put(
      { minutesAgo: 3, day: today, audience: [squad] },
      { kind: 'trained', training: { sport: 'run', minutes: 45 } },
    );
    const swim = await put(
      { minutesAgo: 4, day: yesterday, audience: [] },
      { kind: 'trained', training: { sport: 'swim' } },
    );
    const frisbee = await put(
      { minutesAgo: 2, day: today, audience: [squad] },
      { kind: 'trained', training: { sport: 'custom', customSport: '飞盘', minutes: 30 } },
    );
    await put({ minutesAgo: 1, day: today, audience: [squad] }, { kind: 'healthyMeal', meal: {} });

    const path = `/me/trainings?from=${yesterday}&to=${today}`;
    expect(await call({ method: 'GET', path, token: me.token })).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: {
        version: 1,
        trainings: [
          { id: swim, day: yesterday, sport: 'swim' },
          { id: run, day: today, sport: 'run', minutes: 45 },
          { id: frisbee, day: today, sport: 'custom', customSport: '飞盘', minutes: 30 },
        ],
      },
    });
    expect((await call({ method: 'GET', path, token: friend.token })).body).toStrictEqual({
      version: 1,
      trainings: [],
    });
    expect((await call({ method: 'GET', path })).status).toBe(401);
    const tooLong = '/me/trainings?from=2025-01-01&to=2026-01-07';
    expect((await call({ method: 'GET', path: tooLong, token: me.token })).status).toBe(400);
  });
});

describe('GET /me/records', () => {
  it('works out the member’s records and how they stand in their squad', async () => {
    const [me, coco, loner] = [await signUp(), await signUp(), await signUp()];
    const squad = await squadOf(me, coco);
    const today = new Date().toISOString().slice(0, 10);
    // Rest days don't break a streak, and the default plan never rests two days running, so
    // one of the two days between is a training day whatever the weekday.
    const threeDaysAgo = new Date(Date.parse(today) - 3 * 24 * 60 * 60_000)
      .toISOString()
      .slice(0, 10);
    const madeAt = new Date(Date.now() - 60_000);
    const put = async (
      who: { readonly token: string },
      { day, ...fields }: { readonly day: string } & Readonly<Record<string, unknown>>,
    ) => {
      const id = randomUUID();
      const body = {
        version: 1,
        day,
        createdAt: madeAt.toISOString(),
        audience: [squad],
        ...fields,
      };
      expect(
        (await call({ method: 'PUT', path: `/check-ins/${id}`, token: who.token, body })).status,
      ).toBe(201);
      return id;
    };
    const run = await put(me, {
      day: today,
      kind: 'trained',
      training: { sport: 'run', minutes: 45 },
    });
    // A 补打卡: a day, but not on the clock. Without a time zone on the profile, a day three
    // before the UTC date is one for sure.
    await put(me, {
      day: threeDaysAgo,
      kind: 'trained',
      training: { sport: 'run', minutes: 30 },
    });
    await put(me, { day: today, kind: 'healthyMeal', meal: {} });
    // A 坦白放纵餐 keeps the card's meal 外卡 going, but 健康餐连续 counts 健康餐 only.
    const yesterday = new Date(Date.parse(today) - 24 * 60 * 60_000).toISOString().slice(0, 10);
    await put(me, { day: yesterday, kind: 'cheatMeal', meal: {} });
    const swim = await put(coco, { day: today, kind: 'trained', training: { sport: 'swim' } });
    const react = async (who: { readonly token: string }, id: string) => {
      expect(
        (
          await call({
            method: 'PUT',
            path: `/check-ins/${id}/reactions/mine`,
            token: who.token,
            body: { version: 1, emoji: '🔥' },
          })
        ).status,
      ).toBe(201);
    };
    await react(coco, run);
    await react(me, swim);

    const { status, body } = await call({ method: 'GET', path: '/me/records', token: me.token });
    expect(status).toBe(200);
    const hours = Array.from({ length: 24 }, () => 0);
    hours[madeAt.getUTCHours()] = 1;
    const weekday = (day: string) => (new Date(day).getUTCDay() + 6) % 7;
    const weekdays = Array.from({ length: 7 }, () => 0);
    for (const day of [today, threeDaysAgo])
      weekdays[weekday(day)] = (weekdays[weekday(day)] ?? 0) + 1;
    const cocoId = coco.userId;
    expect(body).toStrictEqual({
      version: 1,
      trainedDays: 2,
      minutes: 75,
      longestMinutes: 45,
      longestStreak: { days: 1, from: today, to: today },
      mealStreak: { days: 1, from: today, to: today },
      currentStreak: { days: 1, from: today, to: today },
      currentMealStreak: { days: 1, from: today, to: today },
      hours,
      weekdays,
      sports: [{ sport: 'run', days: 2 }],
      sportCount: 1,
      squad: {
        id: squad,
        partner: { memberId: cocoId, count: 1 },
        cheersReceived: { count: 1, top: { memberId: cocoId, count: 1 } },
        cheersGiven: { count: 1, top: { memberId: cocoId, count: 1 } },
        firsts: ['topSport', 'mostDays'],
      },
    });

    const alone = await call({ method: 'GET', path: '/me/records', token: loner.token });
    expect(alone.body).toStrictEqual({
      version: 1,
      trainedDays: 0,
      minutes: 0,
      hours: Array(24).fill(0),
      weekdays: Array(7).fill(0),
      sports: [],
      sportCount: 0,
    });
    expect((await call({ method: 'GET', path: '/me/records' })).status).toBe(401);
  });

  it('counts the run still going apart from the record, and leaves out one that broke', async () => {
    const me = await signUp();
    const today = new Date().toISOString().slice(0, 10);
    const daysAgo = (n: number) =>
      new Date(Date.parse(today) - n * 24 * 60 * 60_000).toISOString().slice(0, 10);
    const put = async (day: string, fields: Readonly<Record<string, unknown>>) => {
      const body = {
        version: 1,
        day,
        createdAt: new Date(Date.now() - 60_000).toISOString(),
        audience: [],
        ...fields,
      };
      const path = `/check-ins/${randomUUID()}`;
      expect((await call({ method: 'PUT', path, token: me.token, body })).status).toBe(201);
    };
    const run = { kind: 'trained', training: { sport: 'run' } };
    // Three days in a row, then three without: the default plan never rests two days running,
    // so one of them breaks the run whatever the weekday.
    for (const day of [daysAgo(6), daysAgo(5), daysAgo(4), today]) await put(day, run);
    // A 健康餐 two days ago: yesterday had none, so that run is over.
    await put(daysAgo(2), { kind: 'healthyMeal', meal: {} });

    const { body } = await call({ method: 'GET', path: '/me/records', token: me.token });
    expect(body).toMatchObject({
      longestStreak: { days: 3, from: daysAgo(6), to: daysAgo(4) },
      currentStreak: { days: 1, from: today, to: today },
      mealStreak: { days: 1, from: daysAgo(2), to: daysAgo(2) },
    });
    expect(body).not.toHaveProperty('currentMealStreak');
  });

  it('puts each 训练 on the hour it started: the start picked, else its workout’s', async () => {
    // No time zone on the profile: the member's clock is UTC.
    const me = await signUp();
    const madeAt = new Date(Date.now() - 60_000);
    const day = madeAt.toISOString().slice(0, 10);
    const startedAt = new Date(madeAt.getTime() - 3 * 60 * 60_000);
    const put = async (training: Readonly<Record<string, unknown>>) => {
      const body = {
        version: 1,
        day,
        createdAt: madeAt.toISOString(),
        audience: [],
        kind: 'trained',
        training: { sport: 'run', ...training },
      };
      const path = `/check-ins/${randomUUID()}`;
      expect((await call({ method: 'PUT', path, token: me.token, body })).status).toBe(201);
    };
    const picked = (madeAt.getUTCHours() + 7) % 24;
    await put({ startTime: `${String(picked).padStart(2, '0')}:20` });
    await put({
      workout: {
        provider: 'apple_health',
        providerWorkoutId: randomUUID(),
        startedAt: startedAt.toISOString(),
        endedAt: new Date(startedAt.getTime() + 30 * 60_000).toISOString(),
        summary: { durationSec: 1800 },
      },
    });

    const { body } = await call({ method: 'GET', path: '/me/records', token: me.token });
    const hours = Array.from({ length: 24 }, () => 0);
    hours[picked] = 1;
    hours[startedAt.getUTCHours()] = (hours[startedAt.getUTCHours()] ?? 0) + 1;
    expect(body).toMatchObject({ hours });
  });

  it('stands the member against squadmates only on what they sent the squad', async () => {
    const [me, coco] = [await signUp(), await signUp()];
    const today = new Date().toISOString().slice(0, 10);
    const yesterday = new Date(Date.parse(today) - 24 * 60 * 60_000).toISOString().slice(0, 10);
    const put = async (
      who: { readonly token: string },
      { day, audience }: { readonly day: string; readonly audience: readonly string[] },
    ) => {
      const body = {
        version: 1,
        day,
        createdAt: new Date(Date.now() - 60_000).toISOString(),
        audience,
        kind: 'trained',
        training: { sport: 'run' },
      };
      const path = `/check-ins/${randomUUID()}`;
      expect((await call({ method: 'PUT', path, token: who.token, body })).status).toBe(201);
    };
    // Made before joining: mine, but not the squad's to compare.
    await put(me, { day: yesterday, audience: [] });
    const squad = await squadOf(me, coco);
    await put(me, { day: today, audience: [squad] });
    await put(coco, { day: today, audience: [squad] });

    const { body } = await call({ method: 'GET', path: '/me/records', token: me.token });
    expect(body).toMatchObject({ trainedDays: 2, squad: { firsts: [] } });
  });
});

describe('GET /me/check-in-totals', () => {
  it('counts everything the member ever checked in by kind, 练了 by day', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me);
    // Made a minute ago, for today or a day before it (补打卡): the days are UTC dates, so each
    // stays its own day whatever hour the test runs.
    const madeAt = new Date(Date.now() - 60_000);
    const today = new Date().toISOString().slice(0, 10);
    const daysBefore = (count: number) =>
      new Date(Date.parse(today) - count * 24 * 60 * 60_000).toISOString().slice(0, 10);
    const put = async (day: string, fields: Record<string, unknown>): Promise<number> => {
      const body = {
        version: 1,
        day,
        createdAt: madeAt.toISOString(),
        audience: [squad],
        ...fields,
      };
      const path = `/check-ins/${randomUUID()}`;
      return (await call({ method: 'PUT', path, token: me.token, body })).status;
    };
    const [yesterday, twoDaysAgo] = [daysBefore(1), daysBefore(2)];
    const statuses = [
      await put(today, { kind: 'trained', training: { sport: 'run' } }),
      await put(today, { kind: 'trained', training: { sport: 'swim' } }),
      await put(yesterday, { kind: 'trained', training: { sport: 'run' } }),
      await put(today, { kind: 'healthyMeal', meal: { caption: '沙拉' } }),
      await put(yesterday, { kind: 'healthyMeal', meal: {} }),
      await put(today, { kind: 'cheatMeal', meal: {} }),
      // A 请假条 never goes on a day with a 练了.
      await put(twoDaysAgo, { kind: 'disclaimer', disclaimer: { text: '下雨了' } }),
    ];
    expect(statuses).toStrictEqual([201, 201, 201, 201, 201, 201, 201]);

    expect(
      await call({ method: 'GET', path: '/me/check-in-totals', token: me.token }),
    ).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: {
        version: 1,
        trainedDays: 2,
        healthyMeals: 2,
        cheatMeals: 1,
        disclaimers: 1,
        topSport: { sport: 'run', checkIns: 2 },
        // Yesterday's 健康餐 and today's two meals: any meal keeps the meal streak going.
        streaks: {
          training: { days: 2, from: yesterday, to: today },
          meals: { days: 2, from: yesterday, to: today },
        },
      },
    });
    expect(
      (await call({ method: 'GET', path: '/me/check-in-totals', token: friend.token })).body,
    ).toStrictEqual({
      version: 1,
      trainedDays: 0,
      healthyMeals: 0,
      cheatMeals: 0,
      disclaimers: 0,
      streaks: {},
    });
    expect((await call({ method: 'GET', path: '/me/check-in-totals' })).status).toBe(401);
  });

  it('counts a custom sport by its name for 最常练, and the latest sport wins a tie', async () => {
    const me = await signUp();
    const squad = await squadOf(me);
    const train = async (minutesAgo: number, training: Record<string, unknown>) => {
      const when = new Date(Date.now() - minutesAgo * 60_000);
      const body = {
        version: 1,
        day: when.toISOString().slice(0, 10),
        createdAt: when.toISOString(),
        audience: [squad],
        kind: 'trained',
        training,
      };
      return (
        await call({ method: 'PUT', path: `/check-ins/${randomUUID()}`, token: me.token, body })
      ).status;
    };
    const topSport = async () =>
      z
        .object({ topSport: z.unknown() })
        .parse((await call({ method: 'GET', path: '/me/check-in-totals', token: me.token })).body)
        .topSport;

    expect(await train(5, { sport: 'custom', customSport: '飞盘' })).toBe(201);
    expect(await train(4, { sport: 'custom', customSport: '匹克球' })).toBe(201);
    expect(await topSport()).toStrictEqual({ sport: 'custom', customSport: '匹克球', checkIns: 1 });
    expect(await train(3, { sport: 'custom', customSport: '飞盘' })).toBe(201);
    expect(await topSport()).toStrictEqual({ sport: 'custom', customSport: '飞盘', checkIns: 2 });
  });
});

describe('photos on check-ins', () => {
  const ViewedPhotos = z.object({
    training: z.object({
      photos: z.array(
        z.object({
          path: z.string(),
          url: z.url(),
          size: z.object({ width: z.int(), height: z.int() }).optional(),
        }),
      ),
    }),
  });

  it('saves photos by path, with their sizes, and answers each with a URL to view it', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const [cover, second] = [
      await uploadPhoto(me.token, 'cover'),
      await uploadPhoto(me.token, 'two'),
    ];
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const body = {
      version: 1,
      day,
      createdAt,
      audience: [squad],
      kind: 'trained',
      // A portrait cover, and a photo sent without its size, as older apps do.
      training: {
        sport: 'run',
        photos: [{ path: cover, size: { width: 1080, height: 1350 } }, { path: second }],
      },
    };
    const saved = await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body });
    expect(saved.status).toBe(201);
    const viewed = async (checkIn: unknown) =>
      Promise.all(
        ViewedPhotos.parse(checkIn).training.photos.map(async ({ path, url, size }) => [
          path,
          await (await fetch(url)).text(),
          size,
        ]),
      );
    const expected = [
      [cover, 'cover', { width: 1080, height: 1350 }],
      [second, 'two', undefined],
    ];
    expect(await viewed(saved.body)).toStrictEqual(expected);

    // Sending it again is a retry: the sizes read back the same as they were sent.
    const again = await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body });
    expect(again.status).toBe(200);

    // A squad mate sees them too, through the squad's list.
    const listed = await call({
      method: 'GET',
      path: `/squads/${squad}/check-ins?from=${day}&to=${day}`,
      token: friend.token,
    });
    const [{ checkIn }] = z
      .object({ posts: z.tuple([z.object({ checkIn: z.unknown() })]) })
      .parse(listed.body).posts;
    expect(await viewed(checkIn)).toStrictEqual(expected);
  });

  it('leaves out a photo whose file is gone, and still lists the rest', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const [kept, lost, alone] = [
      await uploadPhoto(me.token, 'kept'),
      await uploadPhoto(me.token, 'lost'),
      await uploadPhoto(me.token, 'alone'),
    ];
    const { day, createdAt } = todayAndNow();
    const [twoPhotos, onePhoto, noPhotos] = [randomUUID(), randomUUID(), randomUUID()];
    const save = (id: string, training: Record<string, unknown>) =>
      call({
        method: 'PUT',
        path: `/check-ins/${id}`,
        token: me.token,
        body: { version: 1, day, createdAt, audience: [squad], kind: 'trained', training },
      });
    expect(
      (await save(twoPhotos, { sport: 'run', photos: [{ path: lost }, { path: kept }] })).status,
    ).toBe(201);
    expect((await save(onePhoto, { sport: 'swim', photos: [{ path: alone }] })).status).toBe(201);
    expect((await save(noPhotos, { sport: 'yoga' })).status).toBe(201);
    // The files go from Storage behind the check-ins' back.
    await photos.delete([PhotoPath.parse(lost), PhotoPath.parse(alone)]);

    const listed = await call({
      method: 'GET',
      path: `/squads/${squad}/check-ins?from=${day}&to=${day}`,
      token: friend.token,
    });
    expect(listed.status).toBe(200);
    const training = new Map(
      z
        .object({
          posts: z.array(
            z.object({
              checkIn: z.object({
                id: z.string(),
                training: z.object({ photos: z.array(z.object({ path: z.string() })).optional() }),
              }),
            }),
          ),
        })
        .parse(listed.body)
        .posts.map(({ checkIn }) => [checkIn.id, checkIn.training.photos?.map(({ path }) => path)]),
    );
    expect(training).toStrictEqual(
      new Map([
        [twoPhotos, [kept]],
        [onePhoto, undefined],
        [noPhotos, undefined],
      ]),
    );
    const one = await call({ method: 'GET', path: `/check-ins/${onePhoto}`, token: me.token });
    expect(one.status).toBe(200);
    expect(one.body).toMatchObject({ checkIn: { id: onePhoto, training: { sport: 'swim' } } });
  });

  it('refuses a photo size of 0 or with one side', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const cover = await uploadPhoto(me.token, 'cover');
    const { day, createdAt } = todayAndNow();
    for (const size of [{ width: 0, height: 1350 }, { width: 1080 }]) {
      const refused = await call({
        method: 'PUT',
        path: `/check-ins/${randomUUID()}`,
        token: me.token,
        body: {
          version: 1,
          day,
          createdAt,
          audience: [squad],
          kind: 'trained',
          training: { sport: 'run', photos: [{ path: cover, size }] },
        },
      });
      expect(refused.status).toBe(400);
    }
  });

  it('saves a disclaimer with a photo, viewed like any other', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const cover = await uploadPhoto(me.token, 'rain');
    const { day, createdAt } = todayAndNow();
    const saved = await call({
      method: 'PUT',
      path: `/check-ins/${randomUUID()}`,
      token: me.token,
      body: {
        version: 1,
        day,
        createdAt,
        audience: [squad],
        kind: 'disclaimer',
        disclaimer: { text: '下雨了', photos: [{ path: cover }] },
      },
    });
    expect(saved.status).toBe(201);
    const listed = await call({
      method: 'GET',
      path: `/squads/${squad}/check-ins?from=${day}&to=${day}`,
      token: friend.token,
    });
    const { posts } = z
      .object({
        posts: z.tuple([
          z.object({
            checkIn: z.object({
              disclaimer: z.object({
                text: z.string(),
                photos: z.array(z.object({ path: z.string(), url: z.url() })),
              }),
            }),
          }),
        ]),
      })
      .parse(listed.body);
    const [
      {
        checkIn: { disclaimer },
      },
    ] = posts;
    expect(disclaimer.text).toBe('下雨了');
    expect(
      await Promise.all(
        disclaimer.photos.map(async ({ path, url }) => [path, await (await fetch(url)).text()]),
      ),
    ).toStrictEqual([[cover, 'rain']]);
  });

  it('refuses a photo that isn’t the caller’s, isn’t uploaded, or is already used', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const put = async (path: string) => {
      const { status, body } = await call({
        method: 'PUT',
        path: `/check-ins/${randomUUID()}`,
        token: me.token,
        body: {
          version: 1,
          day,
          createdAt,
          audience: [squad],
          kind: 'healthyMeal',
          meal: { photos: [{ path }] },
        },
      });
      return [status, z.object({ reason: z.string() }).safeParse(body).data?.reason ?? 'saved'];
    };
    expect(await put(await uploadPhoto(friend.token, 'theirs'))).toStrictEqual([
      403,
      'PHOTO_NOT_YOURS',
    ]);
    expect(await put(`${me.userId}/${randomUUID()}`)).toStrictEqual([400, 'PHOTO_NOT_UPLOADED']);
    const mine = await uploadPhoto(me.token, 'mine');
    expect(await put(mine)).toStrictEqual([201, 'saved']);
    expect(await put(mine)).toStrictEqual([409, 'PHOTO_IN_USE']);
    expect(await put('not-a-photo.jpg')).toStrictEqual([400, 'REQUEST_INVALID']);
  });
});

describe('editing and deleting a post', () => {
  it('lets the author edit it, photos and all, and delete it with its photos', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const [cover, second] = [
      await uploadPhoto(me.token, 'cover'),
      await uploadPhoto(me.token, 'two'),
    ];
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const posted = await call({
      method: 'PUT',
      path: `/check-ins/${id}`,
      token: me.token,
      body: {
        version: 1,
        day,
        createdAt,
        audience: [squad],
        kind: 'cheatMeal',
        meal: { caption: '炸鸡', photos: [{ path: cover }] },
      },
    });
    expect(posted.status).toBe(201);

    const change = {
      version: 1,
      kind: 'cheatMeal',
      meal: { caption: '炸鸡和可乐', photos: [{ path: second }] },
    };
    const byFriend = await call({
      method: 'PATCH',
      path: `/check-ins/${id}`,
      token: friend.token,
      body: change,
    });
    expect([byFriend.status, byFriend.body]).toMatchObject([403, { reason: 'NOT_YOUR_CHECK_IN' }]);
    const otherKind = await call({
      method: 'PATCH',
      path: `/check-ins/${id}`,
      token: me.token,
      body: { version: 1, kind: 'healthyMeal', meal: {} },
    });
    expect([otherKind.status, otherKind.body]).toMatchObject([
      400,
      { reason: 'CHECK_IN_KIND_CHANGED' },
    ]);

    const edited = await call({
      method: 'PATCH',
      path: `/check-ins/${id}`,
      token: me.token,
      body: change,
    });
    expect(edited.status).toBe(200);
    expect(edited.body).toMatchObject({
      id,
      day,
      audience: [squad],
      kind: 'cheatMeal',
      meal: { caption: '炸鸡和可乐', photos: [{ path: second }] },
    });
    // The photo it left out is gone from Storage.
    expect([
      await photos.exists(PhotoPath.parse(cover)),
      await photos.exists(PhotoPath.parse(second)),
    ]).toStrictEqual([false, true]);
    const read = await call({ method: 'GET', path: `/check-ins/${id}`, token: friend.token });
    expect(read.body).toMatchObject({ checkIn: { meal: { caption: '炸鸡和可乐' } } });

    const deleteBy = (token: string) => call({ method: 'DELETE', path: `/check-ins/${id}`, token });
    expect((await deleteBy(friend.token)).status).toBe(403);
    expect((await deleteBy(me.token)).status).toBe(204);
    expect((await deleteBy(me.token)).status).toBe(204);
    expect(await photos.exists(PhotoPath.parse(second))).toBe(false);
    const gone = await call({ method: 'GET', path: `/check-ins/${id}`, token: me.token });
    expect([gone.status, gone.body]).toMatchObject([404, { reason: 'CHECK_IN_NOT_FOUND' }]);
    const editGone = await call({
      method: 'PATCH',
      path: `/check-ins/${id}`,
      token: me.token,
      body: change,
    });
    expect(editGone.status).toBe(404);
  });
});

describe('a 训练 from Apple Health', () => {
  const started = new Date(Date.now() - 40 * 60 * 1000);
  const workout = (id: string, extra: Record<string, unknown> = {}) => ({
    provider: 'apple_health',
    providerWorkoutId: id,
    startedAt: started.toISOString(),
    endedAt: new Date(started.getTime() + 32 * 60 * 1000).toISOString(),
    summary: { durationSec: 1920, distanceM: 5210.5, paceSecPerKm: 369, avgHr: 148 },
    route: [
      { lat: 40.7812, lon: -73.9665 },
      { lat: 40.7821, lon: -73.9651 },
    ],
    tilePosition: 1,
    ...extra,
  });
  const reason = (body: unknown) => z.object({ reason: z.string() }).safeParse(body).data?.reason;

  it('keeps the workout with the post, posts each workout once, and an edit can strike numbers', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const training = { sport: 'run', minutes: 32, workout: workout('A1') };
    const body = { version: 1, day, createdAt, audience: [squad], kind: 'trained', training };
    const saved = await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body });
    expect(saved.status).toBe(201);
    const expected = {
      ...workout('A1'),
      startedAt: started.toISOString(),
      endedAt: new Date(started.getTime() + 32 * 60 * 1000).toISOString(),
    };
    expect(z.object({ training: z.unknown() }).parse(saved.body).training).toStrictEqual({
      sport: 'run',
      minutes: 32,
      workout: expected,
    });

    // A retry is the same post; the friend sees the workout in the feed.
    const retry = await call({ method: 'PUT', path: `/check-ins/${id}`, token: me.token, body });
    expect(retry.status).toBe(200);
    const feed = await call({
      method: 'GET',
      path: `/squads/${squad}/check-ins?from=${day}&to=${day}`,
      token: friend.token,
    });
    expect(JSON.stringify(feed.body)).toContain('"providerWorkoutId":"A1"');

    // The same workout again is refused, from another post id.
    const again = await call({
      method: 'PUT',
      path: `/check-ins/${randomUUID()}`,
      token: me.token,
      body: { ...body, createdAt: new Date().toISOString() },
    });
    expect([again.status, reason(again.body)]).toStrictEqual([409, 'WORKOUT_ALREADY_POSTED']);

    // An edit that strikes heart rate and takes the map off keeps only the rest.
    const edited = await call({
      method: 'PATCH',
      path: `/check-ins/${id}`,
      token: me.token,
      body: {
        version: 1,
        kind: 'trained',
        training: {
          sport: 'run',
          minutes: 32,
          workout: {
            ...workout('A1', { route: undefined, tilePosition: undefined }),
            summary: { durationSec: 1920, distanceM: 5210.5 },
          },
        },
      },
    });
    expect(edited.status).toBe(200);
    const read = await call({ method: 'GET', path: `/check-ins/${id}`, token: friend.token });
    const shown = z
      .object({ checkIn: z.object({ training: z.object({ workout: z.unknown() }) }) })
      .parse(read.body).checkIn.training.workout;
    expect(shown).toStrictEqual({
      provider: 'apple_health',
      providerWorkoutId: 'A1',
      startedAt: expected.startedAt,
      endedAt: expected.endedAt,
      summary: { durationSec: 1920, distanceM: 5210.5 },
    });
    const logged = await db
      .selectFrom('check_in_events')
      .select('entry')
      .where('check_in_id', '=', id)
      .orderBy('id')
      .execute();
    expect(logged.map(({ entry }) => JSON.stringify(entry).includes('"avgHr":148'))).toStrictEqual([
      true,
      false,
    ]);

    // A build from before workouts edits the caption and sends no workout: the post keeps it.
    const older = await call({
      method: 'PATCH',
      path: `/check-ins/${id}`,
      token: me.token,
      body: {
        version: 1,
        kind: 'trained',
        training: { sport: 'run', minutes: 32, caption: '风大' },
      },
    });
    expect(older.status).toBe(200);
    const after = await call({ method: 'GET', path: `/check-ins/${id}`, token: friend.token });
    expect(
      z
        .object({ checkIn: z.object({ training: z.object({ workout: z.unknown() }) }) })
        .parse(after.body).checkIn.training.workout,
    ).toStrictEqual(shown);

    // Deleting the post frees the workout to be posted again.
    expect(
      (await call({ method: 'DELETE', path: `/check-ins/${id}`, token: me.token })).status,
    ).toBe(204);
    const posted = await call({
      method: 'PUT',
      path: `/check-ins/${randomUUID()}`,
      token: me.token,
      body: { ...body, createdAt: new Date().toISOString() },
    });
    expect(posted.status).toBe(201);
  });

  it('keeps a ski day’s runs, drop and top speed, a hike’s climb, a swim’s pace per 100 m and active calories', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const post = async (sport: string, summary: Record<string, unknown>) => {
      const id = randomUUID();
      const { status } = await call({
        method: 'PUT',
        path: `/check-ins/${id}`,
        token: me.token,
        body: {
          version: 1,
          day,
          createdAt,
          audience: [squad],
          kind: 'trained',
          training: { sport, workout: workout(randomUUID(), { summary }) },
        },
      });
      if (status !== 201) return status;
      const read = await call({ method: 'GET', path: `/check-ins/${id}`, token: friend.token });
      return z
        .object({
          checkIn: z.object({
            training: z.object({ workout: z.object({ summary: z.unknown() }) }),
          }),
        })
        .parse(read.body).checkIn.training.workout.summary;
    };
    const ski = { durationSec: 11_040, runs: 12, descentM: 1860.4, topSpeedKmh: 62.4 };
    expect(await post('ski', ski)).toStrictEqual(ski);
    const hike = { durationSec: 12_600, distanceM: 12_600, elevationGainM: 840, avgHr: 118 };
    expect(await post('hike', hike)).toStrictEqual(hike);
    const swim = { durationSec: 2520, distanceM: 1800, paceSecPer100m: 140, avgHr: 136 };
    expect(await post('swim', swim)).toStrictEqual(swim);
    const strength = { durationSec: 3540, avgHr: 124, maxHr: 156, activeEnergyKcal: 312 };
    expect(await post('strength', strength)).toStrictEqual(strength);
    expect(await post('strength', { activeEnergyKcal: -1 })).toBe(400);
    expect(await post('ski', { runs: 0 })).toBe(400);
    expect(await post('ski', { topSpeedKmh: 400 })).toBe(400);
  });

  it('refuses a tile without its data, data without its tile, or a tile past the photos', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const put = async (extra: Record<string, unknown>) => {
      const { status, body } = await call({
        method: 'PUT',
        path: `/check-ins/${randomUUID()}`,
        token: me.token,
        body: {
          version: 1,
          day,
          createdAt,
          audience: [squad],
          kind: 'trained',
          training: { sport: 'run', workout: workout(randomUUID(), extra) },
        },
      });
      return [status, reason(body) ?? 'saved'];
    };
    expect(await put({ tilePosition: undefined })).toStrictEqual([400, 'REQUEST_INVALID']);
    expect(await put({ route: undefined })).toStrictEqual([400, 'REQUEST_INVALID']);
    expect(await put({ tilePosition: 2 })).toStrictEqual([400, 'REQUEST_INVALID']);
    expect(await put({ summary: { avgHr: 400 } })).toStrictEqual([400, 'REQUEST_INVALID']);
    expect(
      await put({
        route: undefined,
        series: {
          hr: [
            { t: 0, bpm: 90 },
            { t: 60, bpm: 120 },
          ],
        },
      }),
    ).toStrictEqual([201, 'saved']);
  });

  it('keeps a 训练’s start time, and an edit changes or clears it', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const put = async (training: Record<string, unknown>, at = id) =>
      (
        await call({
          method: 'PUT',
          path: `/check-ins/${at}`,
          token: me.token,
          body: { version: 1, day, createdAt, audience: [squad], kind: 'trained', training },
        })
      ).status;
    expect(await put({ sport: 'run', startTime: '24:00' }, randomUUID())).toBe(400);
    expect(await put({ sport: 'run', minutes: 30, startTime: '06:05' })).toBe(201);
    const shown = async () =>
      z
        .object({ checkIn: z.object({ training: z.object({ startTime: z.string().optional() }) }) })
        .parse((await call({ method: 'GET', path: `/check-ins/${id}`, token: friend.token })).body)
        .checkIn.training.startTime;
    expect(await shown()).toBe('06:05');

    const edit = async (training: Record<string, unknown>) =>
      (
        await call({
          method: 'PATCH',
          path: `/check-ins/${id}`,
          token: me.token,
          body: { version: 1, kind: 'trained', training },
        })
      ).status;
    expect(await edit({ sport: 'run', startTime: '07:30' })).toBe(200);
    expect(await shown()).toBe('07:30');
    // An edit that leaves it out clears it.
    expect(await edit({ sport: 'run', caption: '早起' })).toBe(200);
    expect(await shown()).toBeUndefined();
  });

  it('names the squadmates a 训练 was done with, and an edit keeps, changes or clears them', async () => {
    const [me, mia, coco, stranger] = [
      await signUp(),
      await signUp(),
      await signUp(),
      await signUp(),
    ];
    const squad = await squadOf(me, mia, coco);
    await squadOf(stranger);
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const put = async (
      trainedWith: readonly string[],
      { at = id, inFeed = true }: { at?: string; inFeed?: boolean } = {},
    ) => {
      const { status, body } = await call({
        method: 'PUT',
        path: `/check-ins/${at}`,
        token: me.token,
        body: {
          version: 1,
          day,
          createdAt,
          audience: [squad],
          inFeed,
          kind: 'trained',
          training: { sport: 'run', trainedWith },
        },
      });
      return [status, reason(body) ?? 'saved'];
    };
    const refused = [400, 'TRAINED_WITH_NOT_SQUADMATE'];
    expect(await put([stranger.userId], { at: randomUUID() })).toStrictEqual(refused);
    expect(await put([me.userId], { at: randomUUID() })).toStrictEqual(refused);
    // A check-in only recorded, off the squad's 动态, names no one.
    expect(await put([mia.userId], { at: randomUUID(), inFeed: false })).toStrictEqual(refused);
    expect(await put([mia.userId, mia.userId], { at: randomUUID() })).toStrictEqual([
      400,
      'REQUEST_INVALID',
    ]);
    // None named is a 训练 like any other.
    expect(await put([], { at: randomUUID() })).toStrictEqual([201, 'saved']);
    expect(await put([mia.userId, coco.userId])).toStrictEqual([201, 'saved']);
    expect(await put([mia.userId, coco.userId])).toStrictEqual([200, 'saved']);

    const shown = async () =>
      z
        .object({
          checkIn: z.object({
            training: z.object({ trainedWith: z.array(z.string()).optional() }),
          }),
        })
        .parse((await call({ method: 'GET', path: `/check-ins/${id}`, token: mia.token })).body)
        .checkIn.training.trainedWith;
    expect(await shown()).toStrictEqual([mia.userId, coco.userId]);

    const edit = async (training: Record<string, unknown>) => {
      const { status, body } = await call({
        method: 'PATCH',
        path: `/check-ins/${id}`,
        token: me.token,
        body: { version: 1, kind: 'trained', training },
      });
      return [status, reason(body) ?? 'saved'];
    };
    // Builds from before tags leave it out: the post keeps them.
    expect(await edit({ sport: 'run', caption: '一起跑' })).toStrictEqual([200, 'saved']);
    expect(await shown()).toStrictEqual([mia.userId, coco.userId]);
    expect(await edit({ sport: 'run', trainedWith: [coco.userId] })).toStrictEqual([200, 'saved']);
    expect(await shown()).toStrictEqual([coco.userId]);
    expect(await edit({ sport: 'run', trainedWith: [stranger.userId] })).toStrictEqual(refused);
    expect(await edit({ sport: 'run', trainedWith: [] })).toStrictEqual([200, 'saved']);
    expect(await shown()).toBeUndefined();
  });

  it('shows a meal’s place to the squad, and an edit changes or clears it', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const place = {
      name: 'Sweetgreen',
      appleId: 'I6FD7682FD36BB3BE',
      category: 'restaurant',
      latitude: 40.7448,
      longitude: -73.9881,
    };
    expect(
      (
        await call({
          method: 'PUT',
          path: `/check-ins/${id}`,
          token: me.token,
          body: {
            version: 1,
            day,
            createdAt,
            audience: [squad],
            kind: 'healthyMeal',
            meal: { place },
          },
        })
      ).status,
    ).toBe(201);
    const shown = async () =>
      z
        .object({ checkIn: z.object({ meal: z.object({ place: z.unknown().optional() }) }) })
        .parse((await call({ method: 'GET', path: `/check-ins/${id}`, token: friend.token })).body)
        .checkIn.meal.place;
    expect(await shown()).toStrictEqual(place);

    const edit = async (meal: Record<string, unknown>) =>
      (
        await call({
          method: 'PATCH',
          path: `/check-ins/${id}`,
          token: me.token,
          body: { version: 1, kind: 'healthyMeal', meal },
        })
      ).status;
    expect(await edit({ place: { ...place, name: 'Whole Foods', appleId: undefined } })).toBe(200);
    expect(await shown()).toStrictEqual({
      name: 'Whole Foods',
      category: 'restaurant',
      latitude: 40.7448,
      longitude: -73.9881,
    });
    // An edit that leaves it out clears it, as with every field of the post.
    expect(await edit({ caption: '沙拉' })).toBe(200);
    expect(await shown()).toBeUndefined();
  });

  it('shows a meal’s 健康 and 好吃 to the squad, and an edit changes them and one without them keeps them', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    expect(
      (
        await call({
          method: 'PUT',
          path: `/check-ins/${id}`,
          token: me.token,
          body: {
            version: 1,
            day,
            createdAt,
            audience: [squad],
            kind: 'healthyMeal',
            meal: { caption: '沙拉', rating: { healthy: 5, tasty: 4 } },
          },
        })
      ).status,
    ).toBe(201);
    const shown = async () =>
      z
        .object({ checkIn: z.object({ meal: z.object({ rating: z.unknown().optional() }) }) })
        .parse((await call({ method: 'GET', path: `/check-ins/${id}`, token: friend.token })).body)
        .checkIn.meal.rating;
    expect(await shown()).toStrictEqual({ healthy: 5, tasty: 4 });

    const edit = async (meal: Record<string, unknown>) =>
      (
        await call({
          method: 'PATCH',
          path: `/check-ins/${id}`,
          token: me.token,
          body: { version: 1, kind: 'healthyMeal', meal },
        })
      ).status;
    expect(await edit({ rating: { healthy: 3, tasty: 6 } })).toBe(400);
    expect(await edit({ rating: { healthy: 3, tasty: 5 } })).toBe(200);
    expect(await shown()).toStrictEqual({ healthy: 3, tasty: 5 });
    // An edit that leaves it out keeps it, as builds from before ratings send their edits.
    expect(await edit({ caption: '沙拉配鸡胸' })).toBe(200);
    expect(await shown()).toStrictEqual({ healthy: 3, tasty: 5 });
  });

  it('keeps the heart-rate zones with the curve, and refuses zones that don’t rise or come without it', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const hr = [
      { t: 0, bpm: 90 },
      { t: 60, bpm: 150 },
    ];
    const zones = { light: 107, moderate: 119, vigorous: 144, peak: 175 };
    const put = async (series: Record<string, unknown>, id = randomUUID()) => {
      const { status, body } = await call({
        method: 'PUT',
        path: `/check-ins/${id}`,
        token: me.token,
        body: {
          version: 1,
          day,
          createdAt,
          audience: [squad],
          kind: 'trained',
          training: { sport: 'run', workout: workout(randomUUID(), { route: undefined, series }) },
        },
      });
      return [status, reason(body) ?? 'saved'];
    };
    expect(await put({ laps: [50, 52], zones })).toStrictEqual([400, 'REQUEST_INVALID']);
    expect(await put({ hr, zones: { ...zones, moderate: 100 } })).toStrictEqual([
      400,
      'REQUEST_INVALID',
    ]);

    const id = randomUUID();
    expect(await put({ hr, zones }, id)).toStrictEqual([201, 'saved']);
    const { body } = await call({ method: 'GET', path: `/check-ins/${id}`, token: friend.token });
    const shown = z
      .object({
        checkIn: z.object({ training: z.object({ workout: z.object({ series: z.unknown() }) }) }),
      })
      .parse(body).checkIn.training.workout.series;
    expect(shown).toStrictEqual({ hr, zones });
  });

  it('keeps a map and a chart together, each in its place, and an older build’s edit keeps both', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const { day, createdAt } = todayAndNow();
    const hr = {
      hr: [
        { t: 0, bpm: 90 },
        { t: 60, bpm: 120 },
      ],
    };
    const photos = [{ path: await uploadPhoto(me.token, 'cover') }];
    const put = async (extra: Record<string, unknown>, id = randomUUID()) => {
      const { status, body } = await call({
        method: 'PUT',
        path: `/check-ins/${id}`,
        token: me.token,
        body: {
          version: 1,
          day,
          createdAt,
          audience: [squad],
          kind: 'trained',
          training: { sport: 'run', photos, workout: workout(randomUUID(), extra) },
        },
      });
      return [status, reason(body) ?? 'saved'];
    };
    // Both need their own places, among the photos or right after them.
    expect(await put({ series: hr })).toStrictEqual([400, 'REQUEST_INVALID']);
    expect(await put({ series: hr, chartPosition: 1 })).toStrictEqual([400, 'REQUEST_INVALID']);
    expect(await put({ series: hr, chartPosition: 4 })).toStrictEqual([400, 'REQUEST_INVALID']);
    expect(await put({ chartPosition: 2 })).toStrictEqual([400, 'REQUEST_INVALID']);

    const id = randomUUID();
    expect(await put({ series: hr, tilePosition: 2, chartPosition: 3 }, id)).toStrictEqual([
      201,
      'saved',
    ]);
    const shown = async () =>
      z
        .object({
          checkIn: z.object({
            training: z.object({
              workout: z.object({
                tilePosition: z.int(),
                chartPosition: z.int(),
                series: z.unknown(),
              }),
            }),
          }),
        })
        .parse((await call({ method: 'GET', path: `/check-ins/${id}`, token: friend.token })).body)
        .checkIn.training.workout;
    expect(await shown()).toStrictEqual({ tilePosition: 2, chartPosition: 3, series: hr });

    // A build from before workouts takes the photo off: both tiles stay, right after none.
    const older = await call({
      method: 'PATCH',
      path: `/check-ins/${id}`,
      token: me.token,
      body: { version: 1, kind: 'trained', training: { sport: 'run', caption: '风大' } },
    });
    expect(older.status).toBe(200);
    expect(await shown()).toStrictEqual({ tilePosition: 1, chartPosition: 2, series: hr });
  });
});

describe('a squad’s places', () => {
  const park = {
    name: 'Central Park',
    appleId: 'I0PARK',
    category: 'park',
    latitude: 40.78,
    longitude: -73.96,
  };
  const noodles = {
    name: '兰州拉面',
    appleId: 'I0NOODLES',
    category: 'restaurant',
    latitude: 40.75,
    longitude: -73.99,
  };

  async function post({
    member,
    squad,
    entry,
    inFeed = true,
  }: {
    readonly member: { readonly token: string };
    readonly squad: string;
    readonly entry: Record<string, unknown>;
    readonly inFeed?: boolean;
  }) {
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const saved = await call({
      method: 'PUT',
      path: `/check-ins/${id}`,
      token: member.token,
      body: {
        version: 1,
        day,
        createdAt,
        audience: [squad],
        ...entry,
        ...(inFeed ? {} : { inFeed }),
      },
    });
    expect(saved.status).toBe(201);
    return id;
  }

  it('lists the places the squad’s posts were tagged with, with no score', async () => {
    const [me, friend, outsider] = [await signUp(), await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    await post({
      member: me,
      squad,
      entry: {
        kind: 'trained',
        training: { sport: 'custom', customSport: '飞盘', place: park },
      },
    });
    await post({
      member: friend,
      squad,
      entry: {
        kind: 'trained',
        training: { sport: 'custom', customSport: '飞盘', place: park },
      },
    });
    await post({
      member: friend,
      squad,
      entry: {
        kind: 'trained',
        training: { sport: 'custom', customSport: '背包', minutes: 40, place: park },
      },
    });
    await post({
      member: me,
      squad,
      entry: {
        kind: 'healthyMeal',
        meal: { place: noodles, rating: { healthy: 4, tasty: 5 } },
      },
    });
    await post({
      member: friend,
      squad,
      entry: {
        kind: 'cheatMeal',
        meal: { place: noodles, rating: { healthy: 2, tasty: 4 } },
      },
    });
    // A post kept out of 动态 and one without Maps' id add nothing.
    await post({
      member: me,
      squad,
      entry: { kind: 'cheatMeal', meal: { place: noodles } },
      inFeed: false,
    });
    await post({
      member: me,
      squad,
      entry: { kind: 'healthyMeal', meal: { place: { ...park, name: '家', appleId: undefined } } },
    });

    // Places have no score: the route to give one is gone.
    expect(
      (
        await call({
          method: 'PUT',
          path: '/me/place-ratings/apple:I0PARK',
          token: me.token,
          body: { version: 1, stars: 5 },
        })
      ).status,
    ).toBe(404);

    const listed = await call({ method: 'GET', path: `/squads/${squad}/places`, token: me.token });
    expect(listed.status).toBe(200);
    const { places, recent } = z
      .object({
        places: z.array(
          z.object({
            key: z.string(),
            place: z.object({ name: z.string() }),
            visits: z.number(),
            people: z.number(),
            stars: z.number().nullable(),
            raters: z.number(),
          }),
        ),
        recent: z.array(
          z.object({
            key: z.string(),
            kind: z.string(),
            stars: z.number().nullable(),
            calorieValue: z.number().nullable(),
            cover: z.unknown().optional(),
            minutes: z.unknown().optional(),
          }),
        ),
      })
      .parse(listed.body);
    expect(
      places.map(({ key, place, visits, people, stars, raters }) => ({
        key,
        name: place.name,
        visits,
        people,
        stars,
        raters,
      })),
    ).toStrictEqual([
      { key: 'apple:I0PARK', name: 'Central Park', visits: 3, people: 2, stars: null, raters: 0 },
      { key: 'apple:I0NOODLES', name: '兰州拉面', visits: 2, people: 2, stars: null, raters: 0 },
    ]);
    // No visit carries a score; none has a cover or minutes when the post had none.
    expect(recent).toStrictEqual([
      expect.objectContaining({
        key: 'apple:I0NOODLES',
        kind: 'cheatMeal',
        stars: null,
        calorieValue: null,
      }),
      expect.objectContaining({
        key: 'apple:I0NOODLES',
        kind: 'healthyMeal',
        stars: null,
        calorieValue: null,
      }),
      expect.objectContaining({
        key: 'apple:I0PARK',
        kind: 'trained',
        stars: null,
        calorieValue: null,
        minutes: 40,
      }),
      expect.objectContaining({
        key: 'apple:I0PARK',
        kind: 'trained',
        stars: null,
        calorieValue: null,
      }),
      expect.objectContaining({
        key: 'apple:I0PARK',
        kind: 'trained',
        stars: null,
        calorieValue: null,
      }),
    ]);
    expect(recent.filter((visit) => visit.cover !== undefined)).toStrictEqual([]);
    expect(recent.filter((visit) => visit.minutes !== undefined)).toHaveLength(1);

    const page = await call({
      method: 'GET',
      path: `/squads/${squad}/places/apple:I0NOODLES`,
      token: friend.token,
    });
    expect(page.status).toBe(200);
    expect(
      z
        .object({ meals: z.unknown(), sports: z.array(z.unknown()), myStars: z.unknown() })
        .parse(page.body),
    ).toStrictEqual({
      myStars: null,
      sports: [],
      // Meals by kind only: a place shows no average of its meals' scores.
      meals: { healthyMeal: 1, cheatMeal: 1, healthy: null, tasty: null, calorieValue: null },
    });
    const parkPage = await call({
      method: 'GET',
      path: `/squads/${squad}/places/apple:I0PARK`,
      token: friend.token,
    });
    expect(
      z
        .object({ sports: z.unknown(), myStars: z.unknown(), stars: z.unknown() })
        .parse(parkPage.body),
    ).toStrictEqual({
      myStars: null,
      stars: null,
      sports: [
        { sport: 'custom', customSport: '飞盘', count: 2 },
        { sport: 'custom', customSport: '背包', count: 1 },
      ],
    });

    expect(
      (await call({ method: 'GET', path: `/squads/${squad}/places/apple:I0NONE`, token: me.token }))
        .status,
    ).toBe(404);
    expect(
      (await call({ method: 'GET', path: `/squads/${squad}/places`, token: outsider.token }))
        .status,
    ).toBe(403);
  });
});

describe('a squad’s own places', () => {
  it('lets every member tag a place one of them added', async () => {
    const [me, friend, outsider] = [await signUp(), await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const id = randomUUID();
    const body = {
      version: 1,
      name: ' 小区健身角 ',
      kind: 'gym',
      latitude: 40.7,
      longitude: -73.9,
    };
    const path = `/squads/${squad}/custom-places/${id}`;
    const added = await call({ method: 'PUT', path, token: me.token, body });
    expect(added.status).toBe(201);
    const view = {
      id,
      name: '小区健身角',
      kind: 'gym',
      latitude: 40.7,
      longitude: -73.9,
      addedBy: me.userId,
    };
    expect(
      z.object({ place: z.object({ addedAt: z.string() }).loose() }).parse(added.body).place,
    ).toMatchObject(view);
    expect((await call({ method: 'PUT', path, token: me.token, body })).status).toBe(200);
    expect(
      (await call({ method: 'PUT', path, token: friend.token, body: { ...body, name: '别处' } }))
        .status,
    ).toBe(409);
    expect((await call({ method: 'PUT', path, token: outsider.token, body })).status).toBe(403);
    expect(
      (await call({ method: 'PUT', path, token: me.token, body: { ...body, kind: 'bar' } })).status,
    ).toBe(400);

    const listed = await call({
      method: 'GET',
      path: `/squads/${squad}/custom-places`,
      token: friend.token,
    });
    expect(listed.status).toBe(200);
    expect(z.object({ places: z.array(z.unknown()) }).parse(listed.body).places).toMatchObject([
      view,
    ]);
    expect(
      (await call({ method: 'GET', path: `/squads/${squad}/custom-places`, token: outsider.token }))
        .status,
    ).toBe(403);

    // A teammate tags their own 训练 with it, and it gets a page under its `squad:` key.
    const { day, createdAt } = todayAndNow();
    const posted = await call({
      method: 'PUT',
      path: `/check-ins/${randomUUID()}`,
      token: friend.token,
      body: {
        version: 1,
        day,
        createdAt,
        audience: [squad],
        kind: 'trained',
        training: {
          sport: 'custom',
          customSport: '壶铃',
          place: { name: '小区健身角', squadPlaceId: id, latitude: 40.7, longitude: -73.9 },
        },
      },
    });
    expect(posted.status).toBe(201);
    const key = `squad:${id}`;
    const page = await call({
      method: 'GET',
      path: `/squads/${squad}/places/${key}`,
      token: me.token,
    });
    expect(page.status).toBe(200);
    expect(
      z
        .object({ key: z.string(), visits: z.number(), stars: z.number().nullable() })
        .parse(page.body),
    ).toStrictEqual({ key, visits: 1, stars: null });
  });

  it('refuses a post tagged with a place its squads don’t have', async () => {
    const [me, outsider] = [await signUp(), await signUp()];
    const squad = await squadOf(me);
    const theirs = await squadOf(outsider);
    const elsewhere = randomUUID();
    expect(
      (
        await call({
          method: 'PUT',
          path: `/squads/${theirs}/custom-places/${elsewhere}`,
          token: outsider.token,
          body: { version: 1, name: '别人家', kind: 'gym', latitude: 1, longitude: 2 },
        })
      ).status,
    ).toBe(201);
    const { day, createdAt } = todayAndNow();
    const tagged = (squadPlaceId: string) => ({
      sport: 'run',
      place: { name: '别人家', squadPlaceId, latitude: 1, longitude: 2 },
    });
    const post = (id: string, squadPlaceId: string) =>
      call({
        method: 'PUT',
        path: `/check-ins/${id}`,
        token: me.token,
        body: {
          version: 1,
          day,
          createdAt,
          audience: [squad],
          kind: 'trained',
          training: tagged(squadPlaceId),
        },
      });
    for (const squadPlaceId of [elsewhere, randomUUID()]) {
      const refused = await post(randomUUID(), squadPlaceId);
      expect([refused.status, refused.body]).toMatchObject([
        400,
        { reason: 'SQUAD_PLACE_NOT_FOUND' },
      ]);
    }

    // Nor can an edit move a post there.
    const id = randomUUID();
    expect(
      (
        await call({
          method: 'PUT',
          path: `/check-ins/${id}`,
          token: me.token,
          body: {
            version: 1,
            day,
            createdAt,
            audience: [squad],
            kind: 'trained',
            training: { sport: 'run' },
          },
        })
      ).status,
    ).toBe(201);
    const edited = await call({
      method: 'PATCH',
      path: `/check-ins/${id}`,
      token: me.token,
      body: { version: 1, kind: 'trained', training: tagged(elsewhere) },
    });
    expect([edited.status, edited.body]).toMatchObject([400, { reason: 'SQUAD_PLACE_NOT_FOUND' }]);
  });
});
