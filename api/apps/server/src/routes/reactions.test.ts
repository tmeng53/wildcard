import { randomBytes, randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createOffSender, createPostgresDeviceStore, createPush } from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import { adminOn, config, signUp } from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';

// Reactions and push devices, through the routes the app calls, on local Supabase.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const members = createMembers({ store: createPostgresProfileStore(db) });
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  accounts: createSupabaseAccounts({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  }),
  revokeAppleSignIn: undefined,
  publicRoutes: unlimitedPublicRoutes,
  photos,
  checkIns: createCheckIns({
    store: createPostgresCheckInStore(db),
    reactions: createPostgresReactionStore(db),
    plans: createPostgresWeeklyPlanStore(db),
    photos,
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  weeklyPlans: createWeeklyPlans({
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  members,
  squads: createSquads({ store: createPostgresSquadStore(db), inviteCodes: randomInviteCodes }),
  push: createPush({ store: createPostgresDeviceStore(db), sender: createOffSender() }),
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  log: createLog(() => undefined),
  admin: adminOn(),
});

async function squadOf(...members: readonly { readonly userId: string }[]) {
  const id = randomUUID();
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${id})`.execute(
    db,
  );
  for (const member of members) {
    await sql`insert into public.squad_members (squad_id, member_id) values (${id}, ${member.userId})`.execute(
      db,
    );
  }
  return id;
}

async function call(
  method: string,
  {
    path,
    token,
    body,
  }: { readonly path: string; readonly token?: string; readonly body?: unknown },
) {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  const response = await app.request(path, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  const parsed: unknown = text === '' ? undefined : JSON.parse(text);
  return { status: response.status, body: parsed };
}

/** A 练了 the member posts to these squads now; its id. */
async function checkIn(token: string, ...audience: string[]) {
  const now = new Date(Date.now() - 60_000);
  const id = randomUUID();
  const { status } = await call('PUT', {
    path: `/check-ins/${id}`,
    token,
    body: {
      version: 1,
      day: now.toISOString().slice(0, 10),
      createdAt: now.toISOString(),
      audience,
      kind: 'trained',
      training: { sport: 'run' },
    },
  });
  expect(status).toBe(201);
  return id;
}

/** The phones the database holds for a member, as the push module will read them. */
async function phonesOf(member: { readonly userId: string }) {
  const { rows } = await sql<{
    token: string;
    environment: string;
  }>`select token, environment from public.push_devices where member_id = ${member.userId} order by token`.execute(
    db,
  );
  return rows;
}

describe('PUT /check-ins/{checkInId}/reactions/mine', () => {
  it('reacts, and the author and teammates read it back', async () => {
    const [tracy, ann, bo] = [await signUp(), await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann, bo));
    const path = `/check-ins/${run}/reactions/mine`;

    const first = await call('PUT', {
      path,
      token: ann.token,
      body: { version: 1, kind: 'cheer' },
    });
    expect(first.status).toBe(201);
    expect(first.body).toMatchObject({ version: 1, member: ann.userId, kind: 'cheer' });
    await call('PUT', { path, token: bo.token, body: { version: 1, kind: 'highlight' } });

    for (const viewer of [tracy, bo]) {
      const listed = await call('GET', {
        path: `/check-ins/${run}/reactions`,
        token: viewer.token,
      });
      expect(listed.status).toBe(200);
      expect(listed.body).toMatchObject({
        version: 1,
        reactions: [
          { member: ann.userId, kind: 'cheer' },
          { member: bo.userId, kind: 'highlight' },
        ],
      });
    }
  });

  it('answers a repeat with 200 and the same reaction, and a change with 200', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann));
    const path = `/check-ins/${run}/reactions/mine`;
    const first = await call('PUT', {
      path,
      token: ann.token,
      body: { version: 1, kind: 'cheer' },
    });
    const again = await call('PUT', {
      path,
      token: ann.token,
      body: { version: 1, kind: 'cheer' },
    });
    const changed = await call('PUT', {
      path,
      token: ann.token,
      body: { version: 1, kind: 'lol' },
    });
    expect([first.status, again.status, changed.status]).toStrictEqual([201, 200, 200]);
    expect(again.body).toStrictEqual(first.body);
    expect(changed.body).toMatchObject({ kind: 'lol' });
  });

  it('shows a teammate only the reactions from squads they share the check-in through', async () => {
    const [tracy, ann, bo] = [await signUp(), await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann), await squadOf(tracy, bo));
    const path = `/check-ins/${run}/reactions/mine`;
    await call('PUT', { path, token: ann.token, body: { version: 1, kind: 'cheer' } });
    await call('PUT', { path, token: bo.token, body: { version: 1, kind: 'lol' } });

    expect(
      await call('GET', { path: `/check-ins/${run}/reactions`, token: ann.token }),
    ).toMatchObject({ status: 200, body: { reactions: [{ member: ann.userId, kind: 'cheer' }] } });
    const forTracy = await call('GET', { path: `/check-ins/${run}/reactions`, token: tracy.token });
    expect(forTracy.body).toMatchObject({
      reactions: [{ member: ann.userId }, { member: bo.userId }],
    });
  });

  it('takes a reaction off with DELETE, safe to repeat', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann));
    const path = `/check-ins/${run}/reactions/mine`;
    await call('PUT', { path, token: ann.token, body: { version: 1, kind: 'cheer' } });
    expect((await call('DELETE', { path, token: ann.token })).status).toBe(204);
    expect((await call('DELETE', { path, token: ann.token })).status).toBe(204);
    expect(
      await call('GET', { path: `/check-ins/${run}/reactions`, token: ann.token }),
    ).toStrictEqual({
      status: 200,
      body: { version: 1, reactions: [] },
    });
  });

  it('refuses your own check-in, an unknown reaction, and a check-in you can’t see', async () => {
    const [tracy, stranger] = [await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy));
    const path = `/check-ins/${run}/reactions/mine`;

    expect(
      await call('PUT', { path, token: tracy.token, body: { version: 1, kind: 'cheer' } }),
    ).toMatchObject({ status: 400, body: { reason: 'OWN_CHECK_IN_REACTION' } });
    expect(
      await call('PUT', { path, token: stranger.token, body: { version: 1, kind: 'steady' } }),
    ).toMatchObject({ status: 400, body: { reason: 'REQUEST_INVALID' } });
    for (const [method, route] of [
      ['PUT', path],
      ['DELETE', path],
      ['GET', `/check-ins/${run}/reactions`],
    ] as const) {
      expect(
        await call(method, {
          path: route,
          token: stranger.token,
          body: method === 'PUT' ? { version: 1, kind: 'cheer' } : undefined,
        }),
      ).toStrictEqual({
        status: 404,
        body: {
          version: 1,
          type: 'about:blank',
          title: 'Not Found',
          status: 404,
          detail: `There is no check-in ${run} you can see.`,
          reason: 'CHECK_IN_NOT_FOUND',
          errorStatus: 'NOT_FOUND',
        },
      });
    }
  });

  it('asks a caller with no token to sign in', async () => {
    expect(
      await call('PUT', {
        path: `/check-ins/${randomUUID()}/reactions/mine`,
        body: { version: 1, kind: 'cheer' },
      }),
    ).toMatchObject({ status: 401, body: { reason: 'AUTH_TOKEN_MISSING' } });
  });
});

describe('/me/devices', () => {
  it('registers a phone, and forgets it when its member signs out on it', async () => {
    const tracy = await signUp();
    const token = randomBytes(32).toString('hex');
    const device = { version: 1, token: token.toUpperCase(), environment: 'sandbox' };
    expect(
      await call('PUT', { path: '/me/devices', token: tracy.token, body: device }),
    ).toStrictEqual({ status: 200, body: { version: 1, token, environment: 'sandbox' } });
    expect(await phonesOf(tracy)).toStrictEqual([{ token, environment: 'sandbox' }]);

    const removal = { path: '/me/devices/remove', token: tracy.token, body: { version: 1, token } };
    expect((await call('POST', removal)).status).toBe(204);
    expect((await call('POST', removal)).status).toBe(204);
    expect(await phonesOf(tracy)).toStrictEqual([]);
  });

  it('leaves another member’s phone alone', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const token = randomBytes(32).toString('hex');
    await call('PUT', {
      path: '/me/devices',
      token: tracy.token,
      body: { version: 1, token, environment: 'production' },
    });
    await call('POST', {
      path: '/me/devices/remove',
      token: ann.token,
      body: { version: 1, token },
    });
    expect(await phonesOf(tracy)).toStrictEqual([{ token, environment: 'production' }]);
  });

  it.each([
    {
      case: 'a token that isn’t hex',
      body: { version: 1, token: 'z'.repeat(64), environment: 'sandbox' },
    },
    {
      case: 'an unknown environment',
      body: { version: 1, token: 'a1'.repeat(32), environment: 'dev' },
    },
    { case: 'no version', body: { token: 'a1'.repeat(32), environment: 'sandbox' } },
  ])('refuses $case', async ({ body }) => {
    const { token } = await signUp();
    expect(await call('PUT', { path: '/me/devices', token, body })).toMatchObject({
      status: 400,
      body: { reason: 'REQUEST_INVALID' },
    });
  });

  it('asks a caller with no token to sign in', async () => {
    expect(
      await call('PUT', {
        path: '/me/devices',
        body: { version: 1, token: 'a1'.repeat(32), environment: 'sandbox' },
      }),
    ).toMatchObject({ status: 401, body: { reason: 'AUTH_TOKEN_MISSING' } });
  });
});
