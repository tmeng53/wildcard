import { randomBytes, randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import {
  createPostgresDeviceStore,
  createPush,
  PushRejectedError,
  type Device,
  type PushNotification,
  type PushSender,
} from '@wildcard/push';
import { sql } from 'kysely';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { config, signUp } from '../test-kit/local-supabase.js';

// Reactions and the push notifications around them, through the routes the app calls, on local
// Supabase. APNs is the one thing stood in for: a sender that records what it was asked to send
// (the real APNs sender is tested against a local HTTP/2 server in @wildcard/push).
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});

const sent: { device: Device; notification: PushNotification }[] = [];
let failSending = false;
const recordingSender: PushSender = {
  send(device, notification) {
    if (failSending) return Promise.reject(new PushRejectedError(403, 'InvalidProviderToken'));
    sent.push({ device, notification });
    return Promise.resolve('sent');
  },
};
const logged: string[] = [];
beforeEach(() => {
  sent.length = 0;
  logged.length = 0;
  failSending = false;
});

const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  photos,
  checkIns: createCheckIns({
    store: createPostgresCheckInStore(db),
    reactions: createPostgresReactionStore(db),
    photos,
    clock: () => new Date(),
  }),
  members: createMembers({ store: createPostgresProfileStore(db) }),
  push: createPush({ store: createPostgresDeviceStore(db), sender: recordingSender }),
  log: createLog((line) => logged.push(line)),
});

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

/** A phone registered for the member, as the app does once notifications are allowed. */
async function phoneOf(token: string) {
  const deviceToken = randomBytes(32).toString('hex');
  expect(
    await call('PUT', {
      path: `/me/devices/${deviceToken}`,
      token,
      body: { version: 1, environment: 'sandbox' },
    }),
  ).toStrictEqual({ status: 200, body: { version: 1, environment: 'sandbox' } });
  return deviceToken;
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
  return { id, day: now.toISOString().slice(0, 10) };
}

const sentTo = (deviceToken: string) =>
  sent.filter(({ device }) => device.token === deviceToken).map(({ notification }) => notification);

describe('a new check-in', () => {
  it('is pushed to each teammate who sees it, not to its author', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const [tracysPhone, annsPhone] = [await phoneOf(tracy.token), await phoneOf(ann.token)];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann));

    expect(sentTo(tracysPhone)).toStrictEqual([]);
    expect(sentTo(annsPhone)).toStrictEqual([
      {
        alert: { key: 'push.checkIn.trained' },
        category: 'checkIn.trained',
        thread: `check-ins:${run.day}`,
        collapseId: `check-in:${tracy.userId}:${run.day}`,
        interruption: 'active',
        event: { type: 'checkIn', checkIn: run.id, member: tracy.userId, kind: 'trained' },
      },
    ]);
  });

  it('is saved even when the push fails, and the failure is logged', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    await phoneOf(ann.token);
    failSending = true;
    await checkIn(tracy.token, await squadOf(tracy, ann));
    expect(logged.some((line) => line.includes('push failed'))).toBe(true);
  });
});

describe('PUT /check-ins/{checkInId}/reactions/mine', () => {
  it('reacts, tells the author with the count, and quiets later reactions', async () => {
    const [tracy, ann, bo] = [await signUp(), await signUp(), await signUp()];
    const tracysPhone = await phoneOf(tracy.token);
    const run = await checkIn(tracy.token, await squadOf(tracy, ann, bo));

    const first = await call('PUT', {
      path: `/check-ins/${run.id}/reactions/mine`,
      token: ann.token,
      body: {
        version: 1,
        kind: 'cheer',
      },
    });
    expect(first.status).toBe(201);
    expect(first.body).toMatchObject({ version: 1, member: ann.userId, kind: 'cheer' });
    await call('PUT', {
      path: `/check-ins/${run.id}/reactions/mine`,
      token: bo.token,
      body: {
        version: 1,
        kind: 'fire',
      },
    });

    expect(sentTo(tracysPhone)).toStrictEqual([
      {
        alert: { key: 'push.reaction.cheer', args: ['1'] },
        category: 'reaction',
        thread: `check-in:${run.id}`,
        collapseId: `reactions:${run.id}`,
        interruption: 'active',
        event: { type: 'reaction', checkIn: run.id, member: ann.userId, kind: 'cheer', count: '1' },
      },
      {
        alert: { key: 'push.reaction.fire', args: ['2'] },
        category: 'reaction',
        thread: `check-in:${run.id}`,
        collapseId: `reactions:${run.id}`,
        interruption: 'passive',
        event: { type: 'reaction', checkIn: run.id, member: bo.userId, kind: 'fire', count: '2' },
      },
    ]);

    const listed = await call('GET', {
      path: `/check-ins/${run.id}/reactions`,
      token: tracy.token,
    });
    expect(listed.status).toBe(200);
    expect(listed.body).toMatchObject({
      version: 1,
      reactions: [
        { member: ann.userId, kind: 'cheer' },
        { member: bo.userId, kind: 'fire' },
      ],
    });
  });

  it('answers a repeat with 200 and doesn’t tell the author again', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const tracysPhone = await phoneOf(tracy.token);
    const run = await checkIn(tracy.token, await squadOf(tracy, ann));
    const path = `/check-ins/${run.id}/reactions/mine`;
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
    expect(sentTo(tracysPhone)).toHaveLength(1);
  });

  it('takes a reaction off with DELETE, safe to repeat', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann));
    const path = `/check-ins/${run.id}/reactions/mine`;
    await call('PUT', { path, token: ann.token, body: { version: 1, kind: 'cheer' } });
    expect((await call('DELETE', { path, token: ann.token })).status).toBe(204);
    expect((await call('DELETE', { path, token: ann.token })).status).toBe(204);
    expect(
      await call('GET', { path: `/check-ins/${run.id}/reactions`, token: ann.token }),
    ).toStrictEqual({
      status: 200,
      body: { version: 1, reactions: [] },
    });
  });

  it('refuses your own check-in, an unknown reaction, and a check-in you can’t see', async () => {
    const [tracy, stranger] = [await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy));
    const path = `/check-ins/${run.id}/reactions/mine`;

    expect(
      await call('PUT', { path, token: tracy.token, body: { version: 1, kind: 'cheer' } }),
    ).toMatchObject({
      status: 400,
      body: { reason: 'OWN_CHECK_IN_REACTION' },
    });
    expect(
      await call('PUT', { path, token: stranger.token, body: { version: 1, kind: 'heart' } }),
    ).toMatchObject({
      status: 400,
      body: { reason: 'REQUEST_INVALID' },
    });
    for (const [method, route] of [
      ['PUT', path],
      ['DELETE', path],
      ['GET', `/check-ins/${run.id}/reactions`],
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
          detail: `There is no check-in ${run.id} you can see.`,
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
        body: {
          version: 1,
          kind: 'cheer',
        },
      }),
    ).toMatchObject({ status: 401, body: { reason: 'AUTH_TOKEN_MISSING' } });
  });
});

describe('/me/devices/{token}', () => {
  it('stops pushes to a phone its member signed out on', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const annsPhone = await phoneOf(ann.token);
    expect(
      (await call('DELETE', { path: `/me/devices/${annsPhone}`, token: ann.token })).status,
    ).toBe(204);
    await checkIn(tracy.token, await squadOf(tracy, ann));
    expect(sentTo(annsPhone)).toStrictEqual([]);
  });

  it.each([
    {
      case: 'a token that isn’t hex',
      path: `/me/devices/${'z'.repeat(64)}`,
      body: { version: 1, environment: 'sandbox' },
    },
    {
      case: 'an unknown environment',
      path: `/me/devices/${'a1'.repeat(32)}`,
      body: { version: 1, environment: 'dev' },
    },
    {
      case: 'no version',
      path: `/me/devices/${'a1'.repeat(32)}`,
      body: { environment: 'sandbox' },
    },
  ])('refuses $case', async ({ path, body }) => {
    const { token } = await signUp();
    expect(await call('PUT', { path, token, body })).toMatchObject({
      status: 400,
      body: { reason: 'REQUEST_INVALID' },
    });
  });
});
