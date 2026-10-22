import { randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresReplyStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import { adminOn, config, noJobs, pushOn, signUp } from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';

// 请假条 replies, through the routes the app calls, on local Supabase.
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
    membership: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
    }),
    reactions: createPostgresReactionStore(db),
    replies: createPostgresReplyStore(db),
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
  push: pushOn(db),
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  log: createLog(() => undefined),
  jobs: noJobs,
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

/** A check-in the member posts to these squads now, a 请假条 unless asked for a 练了; its id. */
async function post(
  kind: 'disclaimer' | 'trained',
  { token, audience }: { readonly token: string; readonly audience: readonly string[] },
) {
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
      ...(kind === 'disclaimer'
        ? { kind, disclaimer: { text: '下雨了，腿说不想动' } }
        : { kind, training: { sport: 'run' } }),
    },
  });
  expect(status).toBe(201);
  return id;
}

const reply = (kind: string) => ({ version: 1, kind });

describe('PUT /check-ins/{checkInId}/replies/mine', () => {
  it('replies, repeats with 200, changes with 200, and the author reads it back', async () => {
    const [tracy, ann, bo] = [await signUp(), await signUp(), await signUp()];
    const excuse = await post('disclaimer', {
      token: tracy.token,
      audience: [await squadOf(tracy, ann, bo)],
    });
    const path = `/check-ins/${excuse}/replies/mine`;

    const first = await call('PUT', { path, token: ann.token, body: reply('approved') });
    const again = await call('PUT', { path, token: ann.token, body: reply('approved') });
    expect([first.status, again.status]).toStrictEqual([201, 200]);
    expect(first.body).toMatchObject({ version: 1, member: ann.userId, kind: 'approved' });
    expect(again.body).toStrictEqual(first.body);
    await call('PUT', { path, token: bo.token, body: reply('hug') });
    const changed = await call('PUT', { path, token: bo.token, body: reply('together') });
    expect(changed).toMatchObject({ status: 200, body: { kind: 'together' } });

    const listed = await call('GET', { path: `/check-ins/${excuse}/replies`, token: tracy.token });
    expect(listed).toMatchObject({
      status: 200,
      body: {
        version: 1,
        replies: [
          { member: ann.userId, kind: 'approved' },
          { member: bo.userId, kind: 'together' },
        ],
      },
    });
  });

  it('refuses your own 请假条, a check-in that isn’t one, and a reply it doesn’t know', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const squad = await squadOf(tracy, ann);
    const excuse = await post('disclaimer', { token: tracy.token, audience: [squad] });
    const run = await post('trained', { token: tracy.token, audience: [squad] });

    expect(
      await call('PUT', {
        path: `/check-ins/${excuse}/replies/mine`,
        token: tracy.token,
        body: reply('approved'),
      }),
    ).toMatchObject({ status: 400, body: { reason: 'OWN_DISCLAIMER_REPLY' } });
    expect(
      await call('PUT', {
        path: `/check-ins/${run}/replies/mine`,
        token: ann.token,
        body: reply('approved'),
      }),
    ).toMatchObject({ status: 400, body: { reason: 'NOT_A_DISCLAIMER' } });
    expect(
      await call('PUT', {
        path: `/check-ins/${excuse}/replies/mine`,
        token: ann.token,
        body: reply('cheer'),
      }),
    ).toMatchObject({ status: 400 });
  });

  it('answers 404 to someone who shares no squad on it, and 401 without a token', async () => {
    const [tracy, stranger] = [await signUp(), await signUp()];
    const excuse = await post('disclaimer', {
      token: tracy.token,
      audience: [await squadOf(tracy)],
    });
    const path = `/check-ins/${excuse}/replies/mine`;

    expect(await call('PUT', { path, token: stranger.token, body: reply('hug') })).toMatchObject({
      status: 404,
      body: { reason: 'CHECK_IN_NOT_FOUND' },
    });
    expect(
      await call('GET', { path: `/check-ins/${excuse}/replies`, token: stranger.token }),
    ).toMatchObject({ status: 404 });
    expect((await call('PUT', { path, body: reply('hug') })).status).toBe(401);
  });
});

describe('DELETE /check-ins/{checkInId}/replies/mine', () => {
  it('takes the reply off, and again is fine, leaving the reaction alone', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const excuse = await post('disclaimer', {
      token: tracy.token,
      audience: [await squadOf(tracy, ann)],
    });
    await call('PUT', {
      path: `/check-ins/${excuse}/replies/mine`,
      token: ann.token,
      body: reply('approved'),
    });
    await call('PUT', {
      path: `/check-ins/${excuse}/reactions/mine`,
      token: ann.token,
      body: { version: 1, kind: 'lol' },
    });

    for (let attempt = 0; attempt < 2; attempt += 1) {
      const removed = await call('DELETE', {
        path: `/check-ins/${excuse}/replies/mine`,
        token: ann.token,
      });
      expect(removed.status).toBe(204);
    }
    expect(
      await call('GET', { path: `/check-ins/${excuse}/replies`, token: tracy.token }),
    ).toStrictEqual({ status: 200, body: { version: 1, replies: [] } });
    expect(
      await call('GET', { path: `/check-ins/${excuse}/reactions`, token: tracy.token }),
    ).toMatchObject({ status: 200, body: { reactions: [{ member: ann.userId, kind: 'lol' }] } });
  });
});
