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
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import {
  scenesOn,
  switchesOn,
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  placesOn,
  savedPlacesOn,
  moderationOn,
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
  unusedCoachMessages,
  unusedCoachLetters,
  ignoredNotices,
  unusedFeedback,
} from '../test-kit/weekly-awards.js';

// Blocking and reporting (App Review guideline 1.2), through the routes the app calls, on
// local Supabase.
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
    squadPlaceOf: () => Promise.resolve(false),
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
  ...placesOn(db),
  savedPlaces: savedPlacesOn(db),
  moderation: moderationOn(db),
  weather: weatherOn(db),
  scenes: scenesOn(db),
  switches: switchesOn(db),
  weeklyAwards: unusedWeeklyAwards,
  unlocks: unusedUnlocks,
  gifts: unusedGifts,
  rewards: noRewards,
  coachHiring: unusedCoachHiring,
  coachActivity: unusedCoachActivity,
  coachMessages: unusedCoachMessages,
  coachLetters: unusedCoachLetters,
  ...ignoredNotices,
  ...unusedFeedback,
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

/** A member who saved a profile, as everyone does right after signing in. */
async function member() {
  const signedUp = await signUp();
  const saved = await call('PUT', {
    path: '/me/profile',
    token: signedUp.token,
    body: { version: 1, timeZone: 'UTC', catchphrase: null },
  });
  expect(saved.status).toBe(200);
  return signedUp;
}

async function feedOf(token: string, squad: string) {
  const day = new Date().toISOString().slice(0, 10);
  const { status, body } = await call('GET', {
    path: `/squads/${squad}/check-ins?from=${day}&to=${day}`,
    token,
  });
  expect(status).toBe(200);
  return z
    .object({
      posts: z.array(
        z.object({
          checkIn: z.object({ id: z.string() }),
          comments: z.array(z.object({ id: z.string(), member: z.string() })),
          reactions: z.array(z.object({ member: z.string() })),
        }),
      ),
    })
    .parse(body).posts;
}

async function comment(token: string, { on: checkInId, text }: { on: string; text: string }) {
  const id = randomUUID();
  const { status } = await call('PUT', {
    path: `/check-ins/${checkInId}/comments/${id}`,
    token,
    body: { version: 1, text },
  });
  expect(status).toBe(201);
  return id;
}

describe('blocking a teammate', () => {
  it('hides each from the other both ways, keeps both in the squad, and undoes on unblock', async () => {
    const [mia, jay, coco] = [await member(), await member(), await member()];
    const squad = await squadOf(mia, jay, coco);
    const jays = await checkIn(jay.token, squad);
    const cocos = await checkIn(coco.token, squad);
    await comment(mia.token, { on: cocos, text: '下次带我' });
    const jaysComment = await comment(jay.token, { on: cocos, text: '它会习惯的' });

    expect((await call('PUT', { path: `/me/blocks/${jay.userId}`, token: mia.token })).status).toBe(
      204,
    );
    expect((await call('PUT', { path: `/me/blocks/${jay.userId}`, token: mia.token })).status).toBe(
      204,
    );

    const miaSees = await feedOf(mia.token, squad);
    expect(miaSees.map((post) => post.checkIn.id)).toStrictEqual([cocos]);
    expect(miaSees[0]?.comments.map((each) => each.member)).toStrictEqual([mia.userId]);
    const jaySees = await feedOf(jay.token, squad);
    expect(
      jaySees.find((post) => post.checkIn.id === cocos)?.comments.map((each) => each.id),
    ).toStrictEqual([jaysComment]);
    expect((await call('GET', { path: `/check-ins/${jays}`, token: mia.token })).status).toBe(404);
    // Coco sees everyone.
    expect((await feedOf(coco.token, squad)).map((post) => post.checkIn.id).sort()).toStrictEqual(
      [jays, cocos].sort(),
    );

    const listed = await call('GET', { path: '/me/blocks', token: mia.token });
    expect(listed.body).toMatchObject({ version: 1, blocked: [{ member: jay.userId }] });
    expect((await call('GET', { path: '/me/blocks', token: jay.token })).body).toStrictEqual({
      version: 1,
      blocked: [],
    });

    expect(
      (await call('DELETE', { path: `/me/blocks/${jay.userId}`, token: mia.token })).status,
    ).toBe(204);
    expect((await feedOf(mia.token, squad)).map((post) => post.checkIn.id).sort()).toStrictEqual(
      [jays, cocos].sort(),
    );
  });

  it('leaves the other out of 拍一拍 both ways', async () => {
    const [mia, jay, coco] = [await member(), await member(), await member()];
    const squad = await squadOf(mia, jay, coco);
    for (const [from, to] of [
      [jay, mia],
      [coco, mia],
      [mia, jay],
    ] as const) {
      const poked = await call('POST', {
        path: `/squads/${squad}/nudges`,
        token: from.token,
        body: { version: 1, to: to.userId, kind: 'poke' },
      });
      expect(poked.status).toBe(201);
    }
    expect((await call('PUT', { path: `/me/blocks/${jay.userId}`, token: mia.token })).status).toBe(
      204,
    );

    const pokes = z.object({
      sent: z.array(z.string()),
      received: z.array(z.object({ from: z.string() })),
    });
    const miaSees = pokes.parse(
      (await call('GET', { path: `/squads/${squad}/nudges?kind=poke`, token: mia.token })).body,
    );
    expect(miaSees.sent).toStrictEqual([]);
    expect(miaSees.received.map((each) => each.from)).toStrictEqual([coco.userId]);
    const jaySees = pokes.parse(
      (await call('GET', { path: `/squads/${squad}/nudges?kind=poke`, token: jay.token })).body,
    );
    expect(jaySees).toMatchObject({ sent: [], received: [] });
  });

  it('refuses oneself and someone who isn’t a member', async () => {
    const mia = await member();
    const self = await call('PUT', { path: `/me/blocks/${mia.userId}`, token: mia.token });
    expect(self).toMatchObject({ status: 400, body: { reason: 'BLOCK_SELF' } });
    const nobody = await call('PUT', { path: `/me/blocks/${randomUUID()}`, token: mia.token });
    expect(nobody).toMatchObject({ status: 404, body: { reason: 'MEMBER_NOT_FOUND' } });
  });
});

describe('POST /reports', () => {
  it('hides a reported post or comment from the reporter only, once per thing', async () => {
    const [mia, jay] = [await member(), await member()];
    const squad = await squadOf(mia, jay);
    const jays = await checkIn(jay.token, squad);
    const miasOwn = await checkIn(mia.token, squad);
    const rude = await comment(jay.token, { on: miasOwn, text: '鞋：我没签这个合同' });

    const id = randomUUID();
    const first = await call('POST', {
      path: '/reports',
      token: mia.token,
      body: { version: 1, id, kind: 'checkIn', checkIn: jays },
    });
    expect(first).toStrictEqual({ status: 201, body: { version: 1, id } });
    const again = await call('POST', {
      path: '/reports',
      token: mia.token,
      body: { version: 1, id: randomUUID(), kind: 'checkIn', checkIn: jays },
    });
    expect(again).toStrictEqual({ status: 200, body: { version: 1, id } });
    const ofComment = await call('POST', {
      path: '/reports',
      token: mia.token,
      body: { version: 1, id: randomUUID(), kind: 'comment', checkIn: miasOwn, item: rude },
    });
    expect(ofComment.status).toBe(201);

    const miaSees = await feedOf(mia.token, squad);
    expect(miaSees.map((post) => post.checkIn.id)).toStrictEqual([miasOwn]);
    expect(miaSees[0]?.comments).toStrictEqual([]);
    expect((await feedOf(jay.token, squad)).map((post) => post.checkIn.id).sort()).toStrictEqual(
      [jays, miasOwn].sort(),
    );

    const { rows } = await sql<{ kind: string; snapshot: unknown; author_id: string }>`
      select kind, snapshot, author_id from public.content_reports
      where member_id = ${mia.userId} order by at, kind
    `.execute(db);
    expect(rows).toStrictEqual([
      { kind: 'checkIn', snapshot: { version: 1, photos: 0 }, author_id: jay.userId },
      {
        kind: 'comment',
        snapshot: { version: 1, words: '鞋：我没签这个合同' },
        author_id: jay.userId,
      },
    ]);
  });

  it('refuses what the member can’t see', async () => {
    const [mia, stranger] = [await member(), await member()];
    const theirs = await checkIn(stranger.token, await squadOf(stranger));
    const post = await call('POST', {
      path: '/reports',
      token: mia.token,
      body: { version: 1, id: randomUUID(), kind: 'checkIn', checkIn: theirs },
    });
    expect(post).toMatchObject({ status: 404, body: { reason: 'CHECK_IN_NOT_FOUND' } });
    const mine = await checkIn(mia.token, await squadOf(mia));
    const noComment = await call('POST', {
      path: '/reports',
      token: mia.token,
      body: { version: 1, id: randomUUID(), kind: 'comment', checkIn: mine, item: randomUUID() },
    });
    expect(noComment).toMatchObject({ status: 404, body: { reason: 'REPORTED_ITEM_NOT_FOUND' } });
  });
});
