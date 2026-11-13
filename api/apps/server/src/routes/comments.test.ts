import { randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import {
  createCoachActivity,
  createPostgresCoachActivity,
  SquadId as CoachSquadId,
} from '@wildcard/coach';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import {
  createNotices,
  createPostgresNoticeStore,
  createPostgresBroadcastStore,
} from '@wildcard/notices';
import {
  DeviceToken,
  MemberId as PushMember,
  apnsPayload,
  type PushNotification,
} from '@wildcard/push';
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
  placeRatingsOn,
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

// Comments on check-ins, through the routes the app calls, on local Supabase.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const members = createMembers({ store: createPostgresProfileStore(db) });
/** Every push sent, to which phone. */
const sent: { readonly token: string; readonly notification: PushNotification }[] = [];
const push = pushOn(db, {
  send: (device, notification) => {
    sent.push({ token: device.token, notification });
    return Promise.resolve('sent');
  },
});
/** Each reply to a coach the route asked the coach to answer. */
const answersAsked: {
  readonly checkIn: string;
  readonly comment: string;
  readonly coach: string;
  readonly squads: readonly string[];
}[] = [];
const coachActivity = createCoachActivity({ store: createPostgresCoachActivity(db) });
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
    coachSpoke: ({ checkIn, squads, coach }) =>
      coachActivity.spoke({
        squads: squads.map((squad) => CoachSquadId.parse(squad)),
        checkIn,
        coach,
      }),
    // 小混 is every squad's coach here.
    coachHired: ({ coach }) => Promise.resolve(coach === 'xiaohun'),
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
  push,
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  aiConsent: aiConsentOn(db),
  nudges: nudgesOn(db),
  placeRatings: placeRatingsOn(db),
  savedPlaces: savedPlacesOn(db),
  weather: weatherOn(db),
  ...unusedFeedback,
  scenes: scenesOn(db),
  switches: switchesOn(db),
  weeklyAwards: unusedWeeklyAwards,
  unlocks: unusedUnlocks,
  gifts: unusedGifts,
  rewards: noRewards,
  coachHiring: unusedCoachHiring,
  coachActivity: unusedCoachActivity,
  coachLetters: unusedCoachLetters,
  // Real, so a comment's notices are read back from 通知.
  notices: createNotices({
    store: createPostgresNoticeStore(db),
    broadcasts: createPostgresBroadcastStore(db),
    clock: () => new Date(),
  }),
  coachNames: ignoredNotices.coachNames,
  liveEvents: ignoredNotices.liveEvents,
  log: createLog(() => undefined),
  jobs: {
    ...noJobs,
    coach: {
      run: () => Promise.reject(new Error('unused')),
      preview: () => Promise.reject(new Error('unused')),
      welcome: () => Promise.resolve(),
      answer: (asked) => {
        answersAsked.push(asked);
        return Promise.resolve();
      },
      checkedIn: () => Promise.resolve(),
    },
  },
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

/** A signed-up member with a nickname and a phone; the phone's token. */
async function withPhone(nickname: string) {
  const signedUp = await signUp();
  const { status } = await call('PUT', {
    path: '/me/profile',
    token: signedUp.token,
    body: {
      version: 1,
      timeZone: 'Asia/Shanghai',
      character: {
        nickname,
        look: { persona: 'deadpan', variants: { body: 'peach' }, colors: {} },
      },
    },
  });
  expect(status).toBe(200);
  const phone = DeviceToken.parse(randomUUID().replaceAll('-', '').repeat(2));
  await push.registerDevice({
    member: PushMember.parse(signedUp.userId),
    device: { token: phone, environment: 'sandbox' },
  });
  return { ...signedUp, phone };
}

/** The member's 通知, newest first. */
async function noticesOf(token: string): Promise<unknown> {
  const { status, body } = await call('GET', { path: '/me/notices', token });
  expect(status).toBe(200);
  return z.object({ notices: z.array(z.unknown()) }).parse(body).notices;
}

/** What each of these phones was sent, as APNs gets it. */
const sentTo = (...phones: readonly string[]) =>
  phones.map((phone) =>
    sent
      .filter(({ token }) => token === phone)
      .map(({ notification }) => apnsPayload(notification)),
  );

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
    const listed = await call('GET', { path: `/check-ins/${run}`, token: bo.token });
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

  it('lets members reply to a coach that spoke under the post, and has it answer', async () => {
    const [tracy, ann, bo] = [await signUp(), await signUp(), await signUp()];
    const squad = await squadOf(tracy, ann);
    const run = await checkIn(tracy.token, squad);
    const toCoach = ({
      token,
      id = randomUUID(),
      ...body
    }: { readonly token: string; readonly id?: string } & Record<string, unknown>) =>
      call('PUT', {
        path: `/check-ins/${run}/comments/${id}`,
        token,
        body: { version: 1, text: '教练你也跑', ...body },
      });

    // The coach hasn't said anything here yet.
    expect(await toCoach({ token: ann.token, replyToCoach: 'xiaohun' })).toMatchObject({
      status: 400,
      body: { reason: 'REPLY_TO_COACH_NOT_FOUND' },
    });
    await sql`insert into public.coach_replies (squad_id, check_in_id, coach_id, text)
      values (${squad}, ${run}, 'xiaohun', '周日也跑？')`.execute(db);
    const id = randomUUID();
    const written = await toCoach({ token: ann.token, replyToCoach: 'xiaohun', id });
    expect(written).toMatchObject({
      status: 201,
      body: { id, member: ann.userId, replyToCoach: 'xiaohun' },
    });
    expect(written.body).not.toHaveProperty('replyTo');
    // A retry saves nothing new and asks for no second answer.
    expect(await toCoach({ token: ann.token, replyToCoach: 'xiaohun', id })).toMatchObject({
      status: 200,
    });
    expect(answersAsked.filter(({ checkIn: at }) => at === run)).toStrictEqual([
      { checkIn: run, comment: id, coach: 'xiaohun', squads: [squad] },
    ]);
    const listed = await call('GET', { path: `/check-ins/${run}`, token: tracy.token });
    expect(listed).toMatchObject({ body: { comments: [{ id, replyToCoach: 'xiaohun' }] } });

    // Never to a coach that said nothing here, nor to a coach and a member at once, nor a
    // coach id that isn't one; and someone outside the squad still can't see the post.
    for (const body of [
      { replyToCoach: 'maotou' },
      { replyToCoach: 'xiaohun', replyTo: tracy.userId },
    ]) {
      expect(await toCoach({ token: ann.token, ...body })).toMatchObject({
        status: 400,
        body: { reason: 'REPLY_TO_COACH_NOT_FOUND' },
      });
    }
    expect(await toCoach({ token: ann.token, replyToCoach: '毛头' })).toMatchObject({
      status: 400,
    });
    expect(await toCoach({ token: bo.token, replyToCoach: 'xiaohun' })).toMatchObject({
      status: 404,
    });
  });

  it('lets members reply to a coach that only answered an @ under the post', async () => {
    const [tracy, ann] = [await signUp(), await signUp()];
    const squad = await squadOf(tracy, ann);
    const run = await checkIn(tracy.token, squad);
    const path = (id: string) => `/check-ins/${run}/comments/${id}`;
    // Ann @s the coach; it answers her, without ever replying to the post itself.
    const asked = randomUUID();
    await call('PUT', {
      path: path(asked),
      token: ann.token,
      body: { version: 1, text: '@小混 这个哪能买', mentionsCoach: 'xiaohun' },
    });
    await sql`insert into public.coach_answers (squad_id, check_in_id, comment_id, coach_id, text)
      values (${squad}, ${run}, ${asked}, 'xiaohun', '先搜二手')`.execute(db);

    const id = randomUUID();
    const written = await call('PUT', {
      path: path(id),
      token: tracy.token,
      body: {
        version: 1,
        text: '她车上这个哪能买',
        replyToCoach: 'xiaohun',
        mentionsCoach: 'xiaohun',
      },
    });
    expect(written).toMatchObject({
      status: 201,
      body: { id, member: tracy.userId, replyToCoach: 'xiaohun' },
    });
    expect(answersAsked.filter(({ comment }) => comment === id)).toStrictEqual([
      { checkIn: run, comment: id, coach: 'xiaohun', squads: [squad] },
    ]);
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
    const listed = await call('GET', { path: `/check-ins/${run}`, token: tracy.token });
    expect(listed.body).toMatchObject({ comments: [] });
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
    const listed = await call('GET', { path: `/check-ins/${run}`, token: tracy.token });
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
    const listed = await call('GET', { path: `/check-ins/${run}`, token: stranger.token });
    expect(listed).toMatchObject({ status: 404, body: { reason: 'CHECK_IN_NOT_FOUND' } });
    expect((await call('GET', { path: `/check-ins/${run}` })).status).toBe(401);
  });

  it('tells the author about a comment and the member replied to about a reply, never the writer', async () => {
    const [tracy, ann, bo] = [
      await withPhone('翠西'),
      await withPhone('安安'),
      await withPhone('波波'),
    ];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann, bo));
    const [first, reply, own] = [randomUUID(), randomUUID(), randomUUID()];
    const comment = (
      id: string,
      { token, ...body }: { token: string; text: string; replyTo?: string },
    ) =>
      call('PUT', {
        path: `/check-ins/${run}/comments/${id}`,
        token,
        body: { version: 1, ...body },
      });

    expect((await comment(first, { token: ann.token, text: '明天我也练腿' })).status).toBe(201);
    // A retry is the same comment: nobody hears of it twice.
    expect((await comment(first, { token: ann.token, text: '明天我也练腿' })).status).toBe(200);
    expect(
      (await comment(reply, { token: bo.token, text: '算我一个', replyTo: ann.userId })).status,
    ).toBe(201);
    // The author on their own post, replying: only the member replied to hears.
    expect(
      (await comment(own, { token: tracy.token, text: '电梯见', replyTo: ann.userId })).status,
    ).toBe(201);

    const told = (key: string, { args, id }: { args: readonly string[]; id: string }) => ({
      version: 1,
      aps: {
        alert: { 'loc-key': key, 'loc-args': args },
        category: 'comment',
        'thread-id': `comments-${run}`,
        'interruption-level': 'passive',
        'mutable-content': 1,
      },
      event: { kind: 'comment', checkIn: run, comment: id },
    });
    expect(sentTo(tracy.phone, ann.phone, bo.phone)).toStrictEqual([
      [
        told('push.comment', { args: ['安安', '明天我也练腿'], id: first }),
        told('push.comment', { args: ['波波', '算我一个'], id: reply }),
      ],
      [
        told('push.comment.reply', { args: ['波波', '算我一个'], id: reply }),
        told('push.comment.reply', { args: ['翠西', '电梯见'], id: own }),
      ],
      [],
    ]);
    // The same words are kept in each member's 通知, newest first, with the post to open.
    expect(await noticesOf(tracy.token)).toMatchObject([
      { kind: 'comment', alert: { key: 'push.comment', args: ['波波', '算我一个'] }, checkIn: run },
      {
        kind: 'comment',
        alert: { key: 'push.comment', args: ['安安', '明天我也练腿'] },
        checkIn: run,
      },
    ]);
    expect(await noticesOf(ann.token)).toMatchObject([
      { kind: 'comment', alert: { key: 'push.comment.reply', args: ['翠西', '电梯见'] } },
      { kind: 'comment', alert: { key: 'push.comment.reply', args: ['波波', '算我一个'] } },
    ]);
    expect(await noticesOf(bo.token)).toStrictEqual([]);
  });

  it('tells each member a comment @s, and has the coach it @s answer', async () => {
    const [tracy, ann, bo] = [
      await withPhone('翠西'),
      await withPhone('安安'),
      await withPhone('波波'),
    ];
    const squad = await squadOf(tracy, ann, bo);
    const run = await checkIn(tracy.token, squad);
    const id = randomUUID();
    const written = await call('PUT', {
      path: `/check-ins/${run}/comments/${id}`,
      token: ann.token,
      body: {
        version: 1,
        text: '@波波 @小混 周六爬山',
        mentions: [bo.userId, ann.userId],
        mentionsCoach: 'xiaohun',
      },
    });
    expect(written).toMatchObject({
      status: 201,
      body: { id, mentions: [bo.userId], mentionsCoach: 'xiaohun' },
    });
    const listed = await call('GET', { path: `/check-ins/${run}`, token: tracy.token });
    expect(listed).toMatchObject({
      body: { comments: [{ id, mentions: [bo.userId], mentionsCoach: 'xiaohun' }] },
    });
    expect(answersAsked.filter(({ checkIn: at }) => at === run)).toStrictEqual([
      { checkIn: run, comment: id, coach: 'xiaohun', squads: [squad] },
    ]);
    expect(sentTo(tracy.phone, ann.phone, bo.phone)).toMatchObject([
      [{ aps: { alert: { 'loc-key': 'push.comment' } } }],
      [],
      [{ aps: { alert: { 'loc-key': 'push.comment.mention' } } }],
    ]);
    expect(await noticesOf(bo.token)).toMatchObject([
      {
        kind: 'comment',
        alert: { key: 'push.comment.mention', args: ['安安', '@波波 @小混 周六爬山'] },
        checkIn: run,
      },
    ]);
    // More than 8 is not a comment.
    const many = await call('PUT', {
      path: `/check-ins/${run}/comments/${randomUUID()}`,
      token: ann.token,
      body: { version: 1, text: '大家', mentions: Array.from({ length: 9 }, () => randomUUID()) },
    });
    expect(many.status).toBe(400);
  });

  it('sends no comment push to a member who turned push off', async () => {
    const [tracy, ann] = [await withPhone('翠西'), await withPhone('安安')];
    const run = await checkIn(tracy.token, await squadOf(tracy, ann));
    const off = { version: 1, settings: { dailyProgress: false } };
    expect(
      (await call('PUT', { path: '/me/push-settings', token: tracy.token, body: off })).status,
    ).toBe(200);
    const written = await call('PUT', {
      path: `/check-ins/${run}/comments/${randomUUID()}`,
      token: ann.token,
      body: { version: 1, text: '加油' },
    });
    expect(written.status).toBe(201);
    expect(sentTo(tracy.phone)).toStrictEqual([[]]);
    // The switch stops the phone, not 通知.
    expect(await noticesOf(tracy.token)).toMatchObject([
      { kind: 'comment', alert: { key: 'push.comment', args: ['安安', '加油'] } },
    ]);
  });
});
