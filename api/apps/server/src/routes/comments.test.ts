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
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
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

// Comments on check-ins, through the routes the app calls, on local Supabase.
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
    comments: createPostgresCommentStore(db),
    plans: createPostgresWeeklyPlanStore(db),
    photos,
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  weeklyPlans: createWeeklyPlans({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  members,
  squads: createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: () => Promise.resolve(true),
  }),
  push: pushOn(db),
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  aiConsent: aiConsentOn(db),
  nudges: nudgesOn(db),
  weeklyAwards: unusedWeeklyAwards,
  weekSummaryWords: unusedWeekSummaryWords,
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

describe('/check-ins/{checkInId}/comments', () => {
  it('writes comments, which the author and teammates read back here and in the feed', async () => {
    const [tracy, ann, bo] = [await signUp(), await signUp(), await signUp()];
    const squad = await squadOf(tracy, ann, bo);
    const run = await checkIn(tracy.token, squad);
    const [first, reply] = [randomUUID(), randomUUID()];

    const written = await call('PUT', {
      path: `/check-ins/${run}/comments/${first}`,
      token: ann.token,
      body: { version: 1, text: '明天我也练腿' },
    });
    expect(written.status).toBe(201);
    expect(written.body).toMatchObject({
      version: 1,
      id: first,
      member: ann.userId,
      text: '明天我也练腿',
    });
    const replied = await call('PUT', {
      path: `/check-ins/${run}/comments/${reply}`,
      token: tracy.token,
      body: { version: 1, text: '电梯见', replyTo: ann.userId },
    });
    expect(replied.status).toBe(201);

    const expected = [
      { id: first, member: ann.userId, text: '明天我也练腿' },
      { id: reply, member: tracy.userId, text: '电梯见', replyTo: ann.userId },
    ];
    const listed = await call('GET', { path: `/check-ins/${run}/comments`, token: bo.token });
    expect(listed).toMatchObject({ status: 200, body: { version: 1, comments: expected } });
    const today = new Date(Date.now() - 60_000).toISOString().slice(0, 10);
    const feed = await call('GET', {
      path: `/squads/${squad}/check-ins?from=${today}&to=${today}`,
      token: bo.token,
    });
    expect(feed).toMatchObject({ status: 200, body: { posts: [{ comments: expected }] } });
  });

  it('answers a retry with 200 and refuses a different comment under the same id', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann));
    const path = `/check-ins/${run}/comments/${randomUUID()}`;
    const first = await call('PUT', { path, token: ann.token, body: { version: 1, text: '冲' } });
    const again = await call('PUT', { path, token: ann.token, body: { version: 1, text: '冲' } });
    expect(again).toStrictEqual({ status: 200, body: first.body });
    const other = await call('PUT', { path, token: ann.token, body: { version: 1, text: '不冲' } });
    expect(other).toMatchObject({ status: 409, body: { reason: 'COMMENT_ID_CONFLICT' } });
  });

  it('refuses a comment that is blank or too long, and a reply to an outsider', async () => {
    const [tracy, ann, stranger] = [await signUp(), await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann));
    for (const body of [
      { version: 1, text: '   ' },
      { version: 1, text: '字'.repeat(101) },
    ]) {
      const refused = await call('PUT', {
        path: `/check-ins/${run}/comments/${randomUUID()}`,
        token: ann.token,
        body,
      });
      expect(refused.status).toBe(400);
    }
    const reply = await call('PUT', {
      path: `/check-ins/${run}/comments/${randomUUID()}`,
      token: ann.token,
      body: { version: 1, text: '你看', replyTo: stranger.userId },
    });
    expect(reply).toMatchObject({ status: 400, body: { reason: 'REPLY_TO_NOT_IN_SQUAD' } });
  });

  it('deletes only the caller’s own comment, safely repeated', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann));
    const path = `/check-ins/${run}/comments/${randomUUID()}`;
    await call('PUT', { path, token: ann.token, body: { version: 1, text: '加油' } });

    const theirs = await call('DELETE', { path, token: tracy.token });
    expect(theirs).toMatchObject({ status: 403, body: { reason: 'NOT_YOUR_COMMENT' } });
    expect((await call('DELETE', { path, token: ann.token })).status).toBe(204);
    expect((await call('DELETE', { path, token: ann.token })).status).toBe(204);
    const listed = await call('GET', { path: `/check-ins/${run}/comments`, token: tracy.token });
    expect(listed.body).toStrictEqual({ version: 1, comments: [] });
  });

  it('lets a member who left the squad delete their own old comment, and nobody else’s', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const squad = await squadOf(tracy, ann);
    const run = await checkIn(tracy.token, squad);
    const mine = `/check-ins/${run}/comments/${randomUUID()}`;
    const tracys = `/check-ins/${run}/comments/${randomUUID()}`;
    await call('PUT', { path: mine, token: ann.token, body: { version: 1, text: '加油' } });
    await call('PUT', { path: tracys, token: tracy.token, body: { version: 1, text: '谢谢' } });
    await sql`delete from public.squad_members where squad_id = ${squad} and member_id = ${ann.userId}`.execute(
      db,
    );

    const others = await call('DELETE', { path: tracys, token: ann.token });
    expect(others).toMatchObject({ status: 404, body: { reason: 'CHECK_IN_NOT_FOUND' } });
    const elsewhere = await checkIn(tracy.token, await squadOf(tracy));
    const wrongPost = mine.replace(run, elsewhere);
    const hidden = await call('DELETE', { path: wrongPost, token: ann.token });
    expect(hidden).toMatchObject({ status: 404, body: { reason: 'CHECK_IN_NOT_FOUND' } });
    expect((await call('DELETE', { path: mine, token: ann.token })).status).toBe(204);
    expect((await call('DELETE', { path: mine, token: ann.token })).status).toBe(204);
    const listed = await call('GET', { path: `/check-ins/${run}/comments`, token: tracy.token });
    expect(listed.body).toMatchObject({ comments: [{ text: '谢谢' }] });
  });

  it('reads one post with its comments, for its author even after they left the squad', async () => {
    const [tracy, ann, stranger] = [await signUp(), await signUp(), await signUp()];
    const squad = await squadOf(tracy, ann);
    const run = await checkIn(tracy.token, squad);
    const id = randomUUID();
    await call('PUT', {
      path: `/check-ins/${run}/comments/${id}`,
      token: tracy.token,
      body: { version: 1, text: '自己先说' },
    });

    const seen = await call('GET', { path: `/check-ins/${run}`, token: ann.token });
    expect(seen).toMatchObject({
      status: 200,
      body: {
        version: 1,
        checkIn: { id: run, member: tracy.userId, audience: [squad] },
        reactions: [],
        comments: [{ id, member: tracy.userId, text: '自己先说' }],
      },
    });
    await sql`delete from public.squad_members where squad_id = ${squad} and member_id = ${tracy.userId}`.execute(
      db,
    );
    const mine = await call('GET', { path: `/check-ins/${run}`, token: tracy.token });
    expect(mine).toMatchObject({ status: 200, body: { comments: [{ id }] } });
    const theirs = await call('GET', { path: `/check-ins/${run}`, token: stranger.token });
    expect(theirs).toMatchObject({ status: 404, body: { reason: 'CHECK_IN_NOT_FOUND' } });
  });

  it('answers 404 to someone who shares no squad on the check-in, and 401 without sign-in', async () => {
    const [tracy, stranger] = [await signUp(), await signUp()];
    const run = await checkIn(tracy.token, await squadOf(tracy));
    const listed = await call('GET', { path: `/check-ins/${run}/comments`, token: stranger.token });
    expect(listed).toMatchObject({ status: 404, body: { reason: 'CHECK_IN_NOT_FOUND' } });
    expect((await call('GET', { path: `/check-ins/${run}/comments` })).status).toBe(401);
  });
});
