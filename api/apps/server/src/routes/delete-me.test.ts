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
import { createOffSender, createPostgresDeviceStore, createPush } from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { AppleAuthorizationCodeInvalidError } from '../errors.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import type { RevokeAppleSignIn } from '../ports.js';
import { adminOn, config, signOut, signUp } from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';

// DELETE /me against local Supabase's Auth, Storage and database. Only Apple is stood in for:
// its servers can't be called without a real key and a real sign-in.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});

function appWith(revokeAppleSignIn: RevokeAppleSignIn | undefined) {
  const logged: unknown[] = [];
  const members = createMembers({ store: createPostgresProfileStore(db) });
  const app = createApp({
    db,
    verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
    accounts: createSupabaseAccounts({
      supabaseUrl: config.supabaseUrl,
      secretKey: config.supabaseSecretKey,
    }),
    revokeAppleSignIn,
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
    push: createPush({ store: createPostgresDeviceStore(db), sender: createOffSender() }),
    disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
    log: createLog((line) => logged.push(JSON.parse(line))),
    admin: adminOn(),
  });
  const call = async (
    ...[method, path, token, body, contentType = 'application/json']: [
      string,
      string,
      string,
      unknown?,
      string?,
    ]
  ) => {
    const response = await app.request(path, {
      method,
      headers: { authorization: `Bearer ${token}`, 'content-type': contentType },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    const text = await response.text();
    const json: unknown = text === '' ? undefined : JSON.parse(text);
    return { status: response.status, body: json };
  };
  return { call, logged };
}

const reasonOf = (body: unknown) => z.object({ reason: z.string() }).parse(body).reason;

/** A squad `creator` makes through the API, which `friend` joins by its invite code. */
async function squadOf(
  call: ReturnType<typeof appWith>['call'],
  [creator, friend]: readonly [{ token: string }, { token: string }],
) {
  const id = randomUUID();
  const made = await call('PUT', `/squads/${id}`, creator.token, { version: 1, name: '早八跑团' });
  expect(made.status).toBe(201);
  const { inviteCode } = z.object({ inviteCode: z.string() }).parse(made.body);
  const joined = await call('POST', `/squad-invites/${inviteCode}/accept`, friend.token);
  expect(joined.status).toBe(201);
  return id;
}

/** A member with a profile, a squad they made and share with a friend, photos and check-ins. */
async function memberWithEverything(call: ReturnType<typeof appWith>['call']) {
  const me = await signUp();
  const friend = await signUp();
  expect(
    (await call('PUT', '/me/profile', me.token, { version: 1, timeZone: 'America/Toronto' }))
      .status,
  ).toBe(200);
  const squad = await squadOf(call, [me, friend]);
  const upload = async () => {
    const { body } = await call('POST', '/photo-uploads', me.token);
    const { path, uploadUrl } = z.object({ path: z.string(), uploadUrl: z.url() }).parse(body);
    const put = await fetch(uploadUrl, {
      method: 'PUT',
      headers: { 'content-type': 'image/jpeg' },
      body: 'JPEG',
    });
    expect(put.ok).toBe(true);
    return path;
  };
  // One photo on a check-in, one uploaded and never used.
  const [onCheckIn] = [await upload(), await upload()];
  const now = new Date(Date.now() - 60_000);
  // Each author's own day: mine in Toronto, which lasts until 3am there; the friend has no time
  // zone yet, so theirs is the UTC day.
  const torontoDay = new Date(now.getTime() - 3 * 3_600_000).toLocaleDateString('en-CA', {
    timeZone: 'America/Toronto',
  });
  const checkIn = (author: { token: string; day: string }, training: Record<string, unknown>) =>
    call('PUT', `/check-ins/${randomUUID()}`, author.token, {
      version: 1,
      day: author.day,
      createdAt: now.toISOString(),
      audience: [squad],
      kind: 'trained',
      training,
    });
  const myCheckIn = await checkIn(
    { ...me, day: torontoDay },
    {
      sport: 'run',
      photos: [{ path: onCheckIn }],
    },
  );
  expect(myCheckIn.status).toBe(201);
  const friendsCheckIn = await checkIn(
    { ...friend, day: now.toISOString().slice(0, 10) },
    { sport: 'swim' },
  );
  expect(friendsCheckIn.status).toBe(201);
  const nextMonday = new Date(now.getTime() + ((8 - now.getUTCDay()) % 7 || 7) * 86_400_000);
  const plan = { version: 1, days: Array.from({ length: 7 }, () => ({ kind: 'rest' })) };
  const weekStart = nextMonday.toISOString().slice(0, 10);
  expect((await call('PUT', `/me/weekly-plans/${weekStart}`, me.token, plan)).status).toBe(200);
  return { me, friend, squad };
}

/**
 * Links an Apple identity to a member, as signing in with Apple does. Local Supabase can't do
 * a real Sign in with Apple, so the test writes Auth's own record of it.
 */
async function linkAppleIdentity(member: string) {
  await sql`insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at, last_sign_in_at)
    values (${randomUUID()}, ${member}, ${JSON.stringify({ sub: member })}::jsonb, 'apple', now(), now(), now())`.execute(
    db,
  );
}

/** How many rows of each kind are the member's, and how many files are in their folder. */
async function whatIsLeftOf(member: string) {
  const count = async (query: ReturnType<typeof sql<{ n: number }>>) =>
    Number((await query.execute(db)).rows[0]?.n);
  const files = await fetch(`${config.supabaseUrl}/storage/v1/object/list/check-in-photos`, {
    method: 'POST',
    headers: { apikey: config.supabaseSecretKey, 'content-type': 'application/json' },
    body: JSON.stringify({ prefix: `${member}/`, limit: 100 }),
  });
  return {
    user: await count(sql`select count(*) as n from auth.users where id = ${member}`),
    profiles: await count(
      sql`select count(*) as n from public.profiles where member_id = ${member}`,
    ),
    checkIns: await count(
      sql`select count(*) as n from public.check_ins where member_id = ${member}`,
    ),
    photoRecords: await count(
      sql`select count(*) as n from public.check_in_photos where path like ${`${member}/%`}`,
    ),
    squadMemberships: await count(
      sql`select count(*) as n from public.squad_members where member_id = ${member}`,
    ),
    squadsMade: await count(
      sql`select count(*) as n from public.squads where created_by = ${member}`,
    ),
    weeklyPlans: await count(
      sql`select count(*) as n from public.weekly_plans where member_id = ${member}`,
    ),
    files: z.array(z.unknown()).parse(await files.json()).length,
  };
}

const nothing = {
  user: 0,
  profiles: 0,
  checkIns: 0,
  photoRecords: 0,
  squadMemberships: 0,
  squadsMade: 0,
  weeklyPlans: 0,
  files: 0,
};
const everything = {
  user: 1,
  profiles: 1,
  checkIns: 1,
  photoRecords: 1,
  squadMemberships: 1,
  squadsMade: 1,
  weeklyPlans: 1,
  files: 2,
};

describe('DELETE /me', () => {
  it('deletes the account and all that is the member’s, and leaves the squad to the others', async () => {
    const { call } = appWith(undefined);
    const { me, friend, squad } = await memberWithEverything(call);
    expect(await whatIsLeftOf(me.userId)).toStrictEqual(everything);

    expect(await call('DELETE', '/me', me.token, { version: 1 })).toStrictEqual({
      status: 204,
      body: undefined,
    });
    expect(await whatIsLeftOf(me.userId)).toStrictEqual(nothing);

    // The squad stays, with the friend in it and their check-in still sent to it.
    const squads = await sql<{
      created_by: string | null;
      members: number;
    }>`select created_by, (select count(*)::int from public.squad_members where squad_id = ${squad}) as members
       from public.squads where id = ${squad}`.execute(db);
    expect(squads.rows).toStrictEqual([{ created_by: null, members: 1 }]);
    const day = new Date(Date.now() - 60_000).toISOString().slice(0, 10);
    const { body } = await call(
      'GET',
      `/squads/${squad}/check-ins?from=${day}&to=${day}`,
      friend.token,
    );
    expect(z.object({ checkIns: z.array(z.unknown()) }).parse(body).checkIns).toHaveLength(1);

    // The deleted session no longer works here.
    const again = await call('DELETE', '/me', me.token, { version: 1 });
    expect([again.status, reasonOf(again.body)]).toStrictEqual([401, 'AUTH_TOKEN_INVALID']);
  });

  it('refuses a session that has signed out, though its token hasn’t expired', async () => {
    const { call } = appWith(undefined);
    const me = await signUp();
    await signOut(me.token);
    const response = await call('DELETE', '/me', me.token, { version: 1 });
    expect([response.status, reasonOf(response.body)]).toStrictEqual([401, 'AUTH_TOKEN_INVALID']);
    expect((await whatIsLeftOf(me.userId)).user).toBe(1);
  });

  it('revokes Sign in with Apple with the app’s code first', async () => {
    const codes: string[] = [];
    const { call } = appWith((code) => {
      codes.push(code);
      return Promise.resolve();
    });
    const me = await signUp();
    const response = await call('DELETE', '/me', me.token, {
      version: 1,
      appleAuthorizationCode: 'c0de',
    });
    expect([response.status, codes, await whatIsLeftOf(me.userId)]).toStrictEqual([
      204,
      ['c0de'],
      nothing,
    ]);
  });

  it('refuses to delete an Apple account without a code, once revocation is set up', async () => {
    const codes: string[] = [];
    const { call } = appWith((code) => {
      codes.push(code);
      return Promise.resolve();
    });
    const { me } = await memberWithEverything(call);
    await linkAppleIdentity(me.userId);
    const refused = await call('DELETE', '/me', me.token, { version: 1 });
    expect([refused.status, reasonOf(refused.body), codes]).toStrictEqual([
      400,
      'APPLE_AUTHORIZATION_CODE_REQUIRED',
      [],
    ]);
    expect(await whatIsLeftOf(me.userId)).toStrictEqual(everything);
    const deleted = await call('DELETE', '/me', me.token, {
      version: 1,
      appleAuthorizationCode: 'c0de',
    });
    expect([deleted.status, codes, await whatIsLeftOf(me.userId)]).toStrictEqual([
      204,
      ['c0de'],
      nothing,
    ]);
  });

  it('deletes an account that doesn’t sign in with Apple without a code', async () => {
    const { call } = appWith(() => Promise.reject(new Error('Apple is not called')));
    const me = await signUp();
    const response = await call('DELETE', '/me', me.token, { version: 1 });
    expect([response.status, await whatIsLeftOf(me.userId)]).toStrictEqual([204, nothing]);
  });

  it('deletes nothing when Apple refuses the code, so the app can retry with a new one', async () => {
    const { call } = appWith(() => Promise.reject(new AppleAuthorizationCodeInvalidError()));
    const { me } = await memberWithEverything(call);
    const response = await call('DELETE', '/me', me.token, {
      version: 1,
      appleAuthorizationCode: 'expired',
    });
    expect([response.status, reasonOf(response.body)]).toStrictEqual([
      400,
      'APPLE_AUTHORIZATION_CODE_INVALID',
    ]);
    expect(await whatIsLeftOf(me.userId)).toStrictEqual(everything);
  });

  it('still deletes, with a warning, while no Apple key is configured', async () => {
    const { call, logged } = appWith(undefined);
    const me = await signUp();
    const response = await call('DELETE', '/me', me.token, {
      version: 1,
      appleAuthorizationCode: 'c0de',
    });
    expect([response.status, (await whatIsLeftOf(me.userId)).user]).toStrictEqual([204, 0]);
    expect(logged).toContainEqual({
      severity: 'WARNING',
      message: 'Sign in with Apple not revoked: no Apple key is configured',
      member: me.userId,
    });
  });

  it('refuses a body not sent as JSON, and deletes nothing', async () => {
    const { call } = appWith(undefined);
    const me = await signUp();
    const response = await call('DELETE', '/me', me.token, { version: 1 }, 'text/plain');
    expect([response.status, reasonOf(response.body)]).toStrictEqual([
      415,
      'MEDIA_TYPE_UNSUPPORTED',
    ]);
    expect((await whatIsLeftOf(me.userId)).user).toBe(1);
  });

  it.each([
    ['no body', undefined],
    ['no version', {}],
    ['an empty code', { version: 1, appleAuthorizationCode: '' }],
    ['an unknown field', { version: 1, reason: 'bye' }],
  ])('refuses %s, and deletes nothing', async (_case, body) => {
    const { call } = appWith(undefined);
    const me = await signUp();
    const response = await call('DELETE', '/me', me.token, body);
    expect([response.status, reasonOf(response.body)]).toStrictEqual([400, 'REQUEST_INVALID']);
    expect((await whatIsLeftOf(me.userId)).user).toBe(1);
  });
});
