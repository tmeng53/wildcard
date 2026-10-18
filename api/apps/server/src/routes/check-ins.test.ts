import { randomUUID } from 'node:crypto';

import { createCheckIns, createPostgresCheckInStore } from '@wildcard/check-ins';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { config, signUp } from '../test-kit/local-supabase.js';

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  photos: createSupabasePhotoStorage({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  }),
  checkIns: createCheckIns({ store: createPostgresCheckInStore(db), clock: () => new Date() }),
  log: createLog(() => undefined),
});

/** A squad with these members. Squads have no routes yet, so the test writes it directly. */
async function squadOf(...members: readonly { readonly userId: string }[]) {
  const id = randomUUID();
  await sql`insert into public.squads (id, name) values (${id}, 'squad')`.execute(db);
  for (const member of members) {
    await sql`insert into public.squad_members (squad_id, member_id) values (${id}, ${member.userId})`.execute(
      db,
    );
  }
  return id;
}

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
      training: { sport: 'custom', customSport: ' 飞盘 ', minutes: 45, caption: '累但爽' },
    };
    const expected = {
      version: 1,
      id,
      member: me.userId,
      day,
      createdAt,
      audience: [squad],
      kind: 'trained',
      training: { sport: 'custom', customSport: '飞盘', minutes: 45, caption: '累但爽' },
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
      meal: { slot: 'dinner' },
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
      meal: { slot: 'dinner' },
    };
    const range = `from=${day}&to=${day}`;

    expect(
      await call({ method: 'GET', path: `/squads/${squad}/check-ins?${range}`, token: me.token }),
    ).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: { version: 1, checkIns: [{ ...saved, audience: [squad] }] },
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
