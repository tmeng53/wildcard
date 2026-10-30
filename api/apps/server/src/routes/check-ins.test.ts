import { randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
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
import { createLog } from '../log.js';
import {
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import { unusedWeeklyAwards, unusedWeekSummaryWords } from '../test-kit/weekly-awards.js';

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
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
  checkIns: createCheckIns({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresCheckInStore(db),
    membership: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent: () => Promise.resolve(true),
    }),
    reactions: createPostgresReactionStore(db),
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
  weeklyAwards: unusedWeeklyAwards,
  weekSummaryWords: unusedWeekSummaryWords,
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
      createdAt,
      audience: [squad],
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
    expect(await put(randomUUID(), disclaimer('下雨'))).toStrictEqual([
      409,
      'application/problem+json',
      'DISCLAIMER_ALREADY_POSTED',
    ]);
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
    const friendsOther = await squadOf(friend);
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
      createdAt,
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

describe('GET /me/check-in-totals', () => {
  it('counts everything the member ever checked in by kind, 练了 by day', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me);
    const yesterday = new Date(Date.now() - 24 * 60 * 60_000);
    const put = async (when: Date, fields: Record<string, unknown>): Promise<number> => {
      const body = {
        version: 1,
        day: when.toISOString().slice(0, 10),
        createdAt: when.toISOString(),
        audience: [squad],
        ...fields,
      };
      const path = `/check-ins/${randomUUID()}`;
      return (await call({ method: 'PUT', path, token: me.token, body })).status;
    };
    const now = new Date(Date.now() - 60_000);
    const statuses = [
      await put(now, { kind: 'trained', training: { sport: 'run' } }),
      await put(now, { kind: 'trained', training: { sport: 'swim' } }),
      await put(yesterday, { kind: 'trained', training: { sport: 'run' } }),
      await put(now, { kind: 'healthyMeal', meal: { caption: '沙拉' } }),
      await put(yesterday, { kind: 'healthyMeal', meal: {} }),
      await put(now, { kind: 'cheatMeal', meal: {} }),
      await put(yesterday, { kind: 'disclaimer', disclaimer: { text: '下雨了' } }),
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
      },
    });
    expect(
      (await call({ method: 'GET', path: '/me/check-in-totals', token: friend.token })).body,
    ).toStrictEqual({ version: 1, trainedDays: 0, healthyMeals: 0, cheatMeals: 0, disclaimers: 0 });
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
    training: z.object({ photos: z.array(z.object({ path: z.string(), url: z.url() })) }),
  });

  it('saves photos by path and answers each with a URL to view it', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await squadOf(me, friend);
    const [cover, second] = [
      await uploadPhoto(me.token, 'cover'),
      await uploadPhoto(me.token, 'two'),
    ];
    const { day, createdAt } = todayAndNow();
    const id = randomUUID();
    const saved = await call({
      method: 'PUT',
      path: `/check-ins/${id}`,
      token: me.token,
      body: {
        version: 1,
        day,
        createdAt,
        audience: [squad],
        kind: 'trained',
        training: { sport: 'run', photos: [{ path: cover }, { path: second }] },
      },
    });
    expect(saved.status).toBe(201);
    const viewed = async (body: unknown) =>
      Promise.all(
        ViewedPhotos.parse(body).training.photos.map(async ({ path, url }) => [
          path,
          await (await fetch(url)).text(),
        ]),
      );
    expect(await viewed(saved.body)).toStrictEqual([
      [cover, 'cover'],
      [second, 'two'],
    ]);

    // A squad mate sees them too, through the squad's list.
    const listed = await call({
      method: 'GET',
      path: `/squads/${squad}/check-ins?from=${day}&to=${day}`,
      token: friend.token,
    });
    const [{ checkIn }] = z
      .object({ posts: z.tuple([z.object({ checkIn: z.unknown() })]) })
      .parse(listed.body).posts;
    expect(await viewed(checkIn)).toStrictEqual([
      [cover, 'cover'],
      [second, 'two'],
    ]);
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
