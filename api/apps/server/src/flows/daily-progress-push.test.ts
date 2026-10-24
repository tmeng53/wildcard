import { randomBytes, randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresReplyStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import {
  MemberId as PushMember,
  createPostgresDailyPushSettings,
  type PushNotification,
  type PushSender,
} from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { jobsTokenScheduler } from '../adapters/scheduler.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import {
  adminOn,
  aiConsentOn,
  config,
  nudgesOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import { unusedWeekSummaryWords, unusedWeeklyAwards } from '../test-kit/weekly-awards.js';
import {
  dailyProgressNotification,
  nudgeInteractions,
  reactionInteractions,
  sendDailyProgress,
} from './daily-progress-push.js';

// The daily progress push, from the routes the app calls to what each phone is sent, on local
// Supabase. Other tests' members share the database, so each test looks only at its own phones.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const members = createMembers({ store: createPostgresProfileStore(db) });
const squads = createSquads({
  store: createPostgresSquadStore(db),
  inviteCodes: randomInviteCodes,
  aiConsent: () => Promise.resolve(true),
});
const checkIns = createCheckIns({
  store: createPostgresCheckInStore(db),
  membership: squads,
  reactions: createPostgresReactionStore(db),
  replies: createPostgresReplyStore(db),
  plans: createPostgresWeeklyPlanStore(db),
  photos,
  calendarOf: memberCalendar(members),
  clock: () => new Date(),
});

/** What each phone was sent, by token. */
const sentTo = new Map<string, PushNotification[]>();
const recorder: PushSender = {
  send(device, notification) {
    sentTo.set(device.token, [...(sentTo.get(device.token) ?? []), notification]);
    return Promise.resolve('sent');
  },
};
const push = pushOn(db, recorder);
const log = createLog(() => undefined);
const JOBS_TOKEN = randomBytes(32).toString('hex');
const nudges = nudgesOn(db);
const interactions = [reactionInteractions(checkIns), nudgeInteractions(nudges)];

const deps = {
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  accounts: createSupabaseAccounts({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  }),
  revokeAppleSignIn: undefined,
  photos,
  checkIns,
  weeklyPlans: createWeeklyPlans({
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  members,
  squads,
  push,
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  weeklyAwards: unusedWeeklyAwards,
  weekSummaryWords: unusedWeekSummaryWords,
  log,
  jobs: { isScheduler: jobsTokenScheduler(JOBS_TOKEN), interactions, clock: () => new Date() },
  admin: adminOn(),
  publicRoutes: unlimitedPublicRoutes,
  aiConsent: aiConsentOn(db),
  nudges,
};
const app = createApp(deps);

const run = () =>
  sendDailyProgress({
    members,
    squads,
    checkIns,
    push,
    interactions,
    clock: () => new Date(),
    log,
  });

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
  const json: unknown = await response.json();
  return { status: response.status, body: json };
}

const HOUR = 3_600_000;

/**
 * A zone whose clock now reads between `from` and `to` o'clock: `Etc/GMT-5` is UTC+5 (the sign
 * is POSIX's, reversed). Offsets from -12 to +14 cover every hour of the day.
 */
function zoneAt(from: number, to: number) {
  const utcHour = new Date().getUTCHours();
  for (let offset = -12; offset <= 14; offset += 1) {
    const hour = (((utcHour + offset) % 24) + 24) % 24;
    if (hour >= from && hour <= to) {
      return {
        zone: offset === 0 ? 'UTC' : `Etc/GMT${offset > 0 ? '-' : '+'}${String(Math.abs(offset))}`,
        offset,
      };
    }
  }
  throw new Error('no zone at that hour');
}
// Well inside the evening and the morning, so a test running across an hour still lands there.
const evening = zoneAt(19, 21);
const morning = zoneAt(8, 11);
/** The day on a clock `offset` hours ahead of UTC (never within 3 hours of midnight here). */
const dayAt = (offset: number) => new Date(Date.now() + offset * HOUR).toISOString().slice(0, 10);

/** A member with a profile in `at`'s zone (and a character called `nickname`) and a phone. */
async function member(at: { readonly zone: string; readonly offset: number }, nickname?: string) {
  const signedUp = await signUp();
  const character =
    nickname === undefined
      ? {}
      : {
          character: {
            nickname,
            look: { persona: 'showoff', variants: { body: 'peach' }, colors: {} },
          },
        };
  const saved = await call('PUT', {
    path: '/me/profile',
    token: signedUp.token,
    body: { version: 1, timeZone: at.zone, ...character },
  });
  expect(saved.status).toBe(200);
  const phone = randomBytes(32).toString('hex');
  const registered = await call('PUT', {
    path: '/me/devices',
    token: signedUp.token,
    body: { version: 1, token: phone, environment: 'production' },
  });
  expect(registered.status).toBe(200);
  return { ...signedUp, phone, offset: at.offset };
}

async function squadOf(...joined: readonly { readonly userId: string }[]) {
  const id = randomUUID();
  const inviteCode = randomInviteCodes();
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${inviteCode})`.execute(
    db,
  );
  for (const each of joined) {
    await sql`insert into public.squad_members (squad_id, member_id) values (${id}, ${each.userId})`.execute(
      db,
    );
  }
  return id;
}

/** The days the member's daily push was handled, from the database. */
async function handled(member: string) {
  const { rows } = await sql<{ day: string; quiet: boolean }>`
    select day::text as day, quiet from public.daily_pushes where member_id = ${member}`.execute(
    db,
  );
  return rows;
}

async function trained(who: { token: string; offset: number }, squad: string) {
  const id = randomUUID();
  const saved = await call('PUT', {
    path: `/check-ins/${id}`,
    token: who.token,
    body: {
      version: 1,
      day: dayAt(who.offset),
      createdAt: new Date(Date.now() - 60_000).toISOString(),
      audience: [squad],
      kind: 'trained',
      training: { sport: 'run' },
    },
  });
  expect(saved.status).toBe(201);
  return id;
}

async function react({
  token,
  checkIn,
  emoji,
}: {
  readonly token: string;
  readonly checkIn: string;
  readonly emoji: string;
}) {
  const reacted = await call('PUT', {
    path: `/check-ins/${checkIn}/reactions/mine`,
    token,
    body: { version: 1, emoji },
  });
  expect(reacted.status).toBe(201);
}

async function nudge(
  from: { readonly token: string },
  { squad, to, kind }: { readonly squad: string; readonly to: { userId: string }; kind: string },
) {
  const sent = await call('POST', {
    path: `/squads/${squad}/nudges`,
    token: from.token,
    body: { version: 1, to: to.userId, kind },
  });
  expect(sent.status).toBe(201);
}

describe('the daily progress push', () => {
  it('sends a member past 6pm their squad’s week and who reacted, each person once, once a day', async () => {
    const eve = await member(evening);
    const [early, other] = [await member(morning), await member(morning)];
    const squad = await squadOf(eve, early, other);
    const [run1, run2] = [await trained(eve, squad), await trained(eve, squad)];
    // Early reacts to both check-ins: still one person.
    await react({ token: early.token, checkIn: run1, emoji: '❤️' });
    await react({ token: early.token, checkIn: run2, emoji: '❤️' });
    await react({ token: other.token, checkIn: run2, emoji: '😂' });

    await run();
    expect(sentTo.get(eve.phone)).toStrictEqual([
      {
        alert: { key: 'push.dailyProgress.received', args: ['1', '15', '2'] },
        category: 'dailyProgress',
        thread: 'dailyProgress',
        collapseId: `dailyProgress-${dayAt(eve.offset)}`,
        interruption: 'passive',
        mutableContent: true,
        event: {
          kind: 'dailyProgress',
          day: dayAt(eve.offset),
          squad,
          // One day trained, of each member's default 5 planned.
          squadTrainedDays: 1,
          squadPlannedDays: 15,
          received: { reaction: 2 },
          // Eve's own posts aren't in her push.
          today: { members: [{ id: eve.userId }], posts: [], more: 0 },
        },
      },
    ]);
    // Their clocks haven't reached 6pm.
    expect(sentTo.get(early.phone)).toBeUndefined();

    await run();
    expect(sentTo.get(eve.phone)).toHaveLength(1);
    expect(await handled(eve.userId)).toStrictEqual([{ day: dayAt(eve.offset), quiet: false }]);
  });

  it('follows the push settings: off for everyone, or at another hour', async () => {
    const [eve, early] = [await member(evening), await member(morning)];
    const squad = await squadOf(eve, early);
    await trained(early, squad);
    const settings = createPostgresDailyPushSettings(db);
    const by = PushMember.parse(eve.userId);
    try {
      await settings.save({ version: 1, sending: false, hour: 18 }, by);
      await run();
      expect(sentTo.get(eve.phone)).toBeUndefined();
      // Nobody's day is marked handled while it is off.
      expect(await handled(eve.userId)).toStrictEqual([]);

      // At 7am, the morning member's clock is past the hour too.
      await settings.save({ version: 1, sending: true, hour: 7 }, by);
      await run();
      expect(sentTo.get(early.phone)).toHaveLength(1);
      expect(sentTo.get(eve.phone)).toHaveLength(1);
    } finally {
      await settings.save({ version: 1, sending: true, hour: 18 }, by);
    }
  });

  it('stays quiet on a day the squad didn’t check in and nothing came in, even if it does later', async () => {
    const [eve, mate] = [await member(evening), await member(evening)];
    const squad = await squadOf(eve, mate);
    await run();
    await trained(mate, squad);
    await run();
    expect(sentTo.get(eve.phone)).toBeUndefined();
    expect(sentTo.get(mate.phone)).toBeUndefined();
    expect(await handled(eve.userId)).toStrictEqual([{ day: dayAt(eve.offset), quiet: true }]);
  });

  it('names who poked them, and a poke alone is worth a push', async () => {
    const [eve, mate] = [await member(evening), await member(morning, '小美')];
    const squad = await squadOf(eve, mate);
    await nudge(mate, { squad, to: eve, kind: 'poke' });
    await run();
    expect(sentTo.get(eve.phone)).toMatchObject([
      {
        alert: { key: 'push.dailyProgress.poke', args: ['0', '10', '小美'] },
        // The push's view shows who patted, by their character and nickname.
        event: {
          received: { poke: 1 },
          today: {
            members: [{ id: eve.userId }, { id: mate.userId, name: '小美' }],
            posts: [],
            pokedBy: [1],
          },
        },
      },
    ]);
  });

  it('names a poker who has a nickname, and counts the other pokers', async () => {
    const eve = await member(evening);
    const [anonymous, poker, fan] = [
      await member(morning),
      await member(morning, '小美'),
      await member(morning),
    ];
    const squad = await squadOf(eve, anonymous, poker, fan);
    await nudge(anonymous, { squad, to: eve, kind: 'poke' });
    await nudge(poker, { squad, to: eve, kind: 'poke' });
    await react({ token: fan.token, checkIn: await trained(eve, squad), emoji: '❤️' });
    await run();
    expect(sentTo.get(eve.phone)).toMatchObject([
      {
        // The fan's reaction is in `event`, not the count: 「小美和另外 1 人拍了拍你」.
        alert: { key: 'push.dailyProgress.poke.more', args: ['1', '20', '小美', '1'] },
        event: { received: { reaction: 1, poke: 2 } },
      },
    ]);
  });

  it('counts a nudge from someone without a nickname without naming them', async () => {
    const [eve, mate] = [await member(evening), await member(morning)];
    const squad = await squadOf(eve, mate);
    await nudge(mate, { squad, to: eve, kind: 'poke' });
    await run();
    expect(sentTo.get(eve.phone)).toMatchObject([
      { alert: { key: 'push.dailyProgress.received', args: ['0', '10', '1'] } },
    ]);
  });

  it('counts from the last push on, so a reaction is never counted twice', async () => {
    const [eve, mate] = [await member(evening), await member(morning)];
    const squad = await squadOf(eve, mate);
    await react({ token: mate.token, checkIn: await trained(eve, squad), emoji: '❤️' });
    // Yesterday's push went out after that reaction, so it carried it.
    const yesterday = new Date(Date.parse(dayAt(eve.offset)) - 24 * HOUR)
      .toISOString()
      .slice(0, 10);
    await sql`insert into public.daily_pushes (member_id, day, quiet, handled_at)
      values (${eve.userId}, ${yesterday}, false, now())`.execute(db);
    await run();
    expect(sentTo.get(eve.phone)).toMatchObject([
      { alert: { key: 'push.dailyProgress', args: ['1', '10'] }, event: { received: {} } },
    ]);
  });

  it('looks back to 6pm the day before on their clock when there was no push before', async () => {
    const eve = await member(evening);
    const [before, after] = [await member(morning), await member(morning)];
    const squad = await squadOf(eve, before, after);
    const checkIn = await trained(eve, squad);
    await react({ token: before.token, checkIn, emoji: '❤️' });
    await react({ token: after.token, checkIn, emoji: '❤️' });
    // 6pm yesterday on eve's clock, `offset` hours ahead of UTC.
    const sixPm = Date.parse(dayAt(eve.offset)) - 24 * HOUR + (18 - eve.offset) * HOUR;
    const at = (member: string, ms: number) =>
      sql`update public.check_in_reactions set reacted_at = ${new Date(ms)}
        where check_in_id = ${checkIn} and member_id = ${member}`.execute(db);
    await at(before.userId, sixPm - 60_000);
    await at(after.userId, sixPm + 60_000);
    await run();
    expect(sentTo.get(eve.phone)).toMatchObject([
      { alert: { args: ['1', '15', '1'] }, event: { received: { reaction: 1 } } },
    ]);
  });

  it('leaves out a reaction from a teammate no longer in the squad the check-in went to', async () => {
    const [eve, mate] = [await member(evening), await member(morning)];
    const first = await squadOf(eve, mate);
    // Still teammates, in another squad.
    await squadOf(eve, mate);
    await react({ token: mate.token, checkIn: await trained(eve, first), emoji: '❤️' });
    await sql`delete from public.squad_members where squad_id = ${first} and member_id = ${mate.userId}`.execute(
      db,
    );
    await run();
    expect(sentTo.get(eve.phone)).toMatchObject([
      { alert: { key: 'push.dailyProgress' }, event: { squad: first, received: {} } },
    ]);
  });

  it('carries teammates’ posts today, newest first, with their reactions and names', async () => {
    // The 请假条 is someone else's: a 练了 the same day would take it back.
    const [eve, mate, third, resting] = [
      await member(evening),
      await member(evening),
      await member(morning),
      await member(evening),
    ];
    const squad = await squadOf(eve, mate, third, resting);
    await call('PUT', {
      path: '/me/profile',
      token: mate.token,
      body: {
        version: 1,
        timeZone: evening.zone,
        character: {
          nickname: '小米',
          look: { persona: 'deadpan', variants: { body: 'peach' }, colors: {} },
        },
      },
    });
    const older = await trained(mate, squad);
    const id = randomUUID();
    const long =
      '腿说今天它请假，我尊重它的决定，明天再说。腿说今天它请假，我尊重它的决定，明天再说。';
    expect(
      (
        await call('PUT', {
          path: `/check-ins/${id}`,
          token: resting.token,
          body: {
            version: 1,
            day: dayAt(resting.offset),
            createdAt: new Date(Date.now() - 30_000).toISOString(),
            audience: [squad],
            kind: 'disclaimer',
            disclaimer: { text: long },
          },
        })
      ).status,
    ).toBe(201);
    await react({ token: third.token, checkIn: older, emoji: '💪' });
    await react({ token: eve.token, checkIn: older, emoji: '😂' });
    // The morning teammate's post is on their own today, and in it too.
    const theirs = await trained(third, squad);
    const anyTime: unknown = expect.any(String);
    await run();
    const [sent] = sentTo.get(eve.phone) ?? [];
    expect(sent?.event.today).toStrictEqual({
      members: [
        { id: eve.userId },
        { id: resting.userId },
        { id: third.userId },
        { id: mate.userId, name: '小米' },
      ],
      posts: [
        {
          id,
          by: 1,
          kind: 'disclaimer',
          at: anyTime,
          text: `${Array.from(long).slice(0, 39).join('')}…`,
          reactions: [],
          reactionCount: 0,
        },
        {
          id: theirs,
          by: 2,
          kind: 'trained',
          sport: 'run',
          at: anyTime,
          reactions: [],
          reactionCount: 0,
        },
        {
          id: older,
          by: 3,
          kind: 'trained',
          sport: 'run',
          at: anyTime,
          reactions: [
            [0, '😂'],
            [2, '💪'],
          ],
          reactionCount: 2,
        },
      ],
      more: 0,
    });
  });

  it('carries at most 4 posts and counts the rest', async () => {
    const [eve, mate] = [await member(evening), await member(evening)];
    const squad = await squadOf(eve, mate);
    for (let each = 0; each < 6; each += 1) await trained(mate, squad);
    await run();
    const [sent] = sentTo.get(eve.phone) ?? [];
    expect(sent?.event.today).toMatchObject({ posts: [{}, {}, {}, {}], more: 2 });
  });

  it('sends nothing to a member who turned it off', async () => {
    const eve = await member(evening);
    const mate = await member(morning);
    const squad = await squadOf(eve, mate);
    await trained(eve, squad);
    expect(await call('GET', { path: '/me/push-settings', token: eve.token })).toStrictEqual({
      status: 200,
      body: { version: 1, settings: { dailyProgress: true } },
    });
    const off = { version: 1, settings: { dailyProgress: false } };
    expect(
      await call('PUT', { path: '/me/push-settings', token: eve.token, body: off }),
    ).toStrictEqual({ status: 200, body: off });
    expect(await call('GET', { path: '/me/push-settings', token: eve.token })).toStrictEqual({
      status: 200,
      body: off,
    });
    await run();
    expect(sentTo.get(eve.phone)).toBeUndefined();
  });

  it('says only the squad’s week when nothing came in', () => {
    expect(
      dailyProgressNotification({
        day: '2026-10-19',
        squad: 'squad',
        squadWeek: { trainedDays: 14, plannedDays: 22 },
        received: new Map([['reaction', new Set<string>()]]),
        today: { members: [{ id: 'me' }], posts: [], more: 0 },
      }),
    ).toMatchObject({
      alert: { key: 'push.dailyProgress', args: ['14', '22'] },
      event: { received: { reaction: 0 } },
    });
  });
});

describe('POST /squads/{squadId}/nudges', () => {
  it('sends one poke a day, so the same again is safe', async () => {
    const [ann, bo] = [await member(morning), await member(morning)];
    const squad = await squadOf(ann, bo);
    const body = { version: 1, to: bo.userId, kind: 'poke' };
    const path = `/squads/${squad}/nudges`;
    expect(await call('POST', { path, token: ann.token, body })).toStrictEqual({
      status: 201,
      body,
    });
    expect(await call('POST', { path, token: ann.token, body })).toStrictEqual({
      status: 200,
      body,
    });
    expect(
      await call('POST', { path, token: bo.token, body: { ...body, to: ann.userId } }),
    ).toMatchObject({ status: 201 });
  });

  it('refuses outsiders, someone outside the squad, oneself and other kinds', async () => {
    const [ann, bo, outsider] = [
      await member(morning),
      await member(morning),
      await member(morning),
    ];
    const squad = await squadOf(ann, bo);
    const path = `/squads/${squad}/nudges`;
    const send = (token: string, { to, kind = 'poke' }: { to: string; kind?: string }) =>
      call('POST', { path, token, body: { version: 1, to, kind } });
    expect(await send(outsider.token, { to: bo.userId })).toMatchObject({
      status: 403,
      body: { reason: 'SQUAD_NOT_JOINED' },
    });
    expect(await send(ann.token, { to: outsider.userId })).toMatchObject({
      status: 404,
      body: { reason: 'NOT_A_SQUADMATE' },
    });
    expect(await send(ann.token, { to: ann.userId })).toMatchObject({
      status: 400,
      body: { reason: 'OWN_NUDGE' },
    });
    expect(await send(ann.token, { to: bo.userId, kind: 'rest' })).toMatchObject({ status: 400 });
    expect(
      await app.request(path, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ version: 1, to: bo.userId, kind: 'poke' }),
      }),
    ).toMatchObject({ status: 401 });
  });
});

describe('GET /squads/{squadId}/nudges', () => {
  it('says whom the caller poked today and who poked them', async () => {
    const [ann, bo, cy, outsider] = [
      await member(morning),
      await member(morning),
      await member(morning),
      await member(morning),
    ];
    const squad = await squadOf(ann, bo, cy);
    await nudge(ann, { squad, to: bo, kind: 'poke' });
    await nudge(cy, { squad, to: ann, kind: 'poke' });
    const path = `/squads/${squad}/nudges?kind=poke`;
    const aTime: unknown = expect.any(String);
    const mine = await call('GET', { path, token: ann.token });
    expect(mine).toStrictEqual({
      status: 200,
      body: {
        version: 1,
        kind: 'poke',
        sent: [bo.userId],
        received: [{ from: cy.userId, at: aTime }],
      },
    });
    expect(await call('GET', { path, token: outsider.token })).toMatchObject({
      status: 403,
      body: { reason: 'SQUAD_NOT_JOINED' },
    });
    expect(
      await call('GET', { path: `/squads/${squad}/nudges?kind=rest`, token: ann.token }),
    ).toMatchObject({ status: 400 });
    expect(await app.request(path)).toMatchObject({ status: 401 });
  });
});

describe('POST /jobs/daily-progress-push', () => {
  const aCount: unknown = expect.any(Number);
  const start = (authorization?: string) =>
    app.request('/jobs/daily-progress-push', {
      method: 'POST',
      headers: authorization === undefined ? {} : { authorization },
    });

  it('runs for the scheduler, and only with its token', async () => {
    const ran = await start(`Bearer ${JOBS_TOKEN}`);
    expect(ran.status).toBe(200);
    expect(await ran.json()).toMatchObject({
      version: 1,
      due: aCount,
      sent: aCount,
      unsent: aCount,
      quiet: aCount,
      skipped: aCount,
      // Other tests write squads straight into the database, with invite codes no real squad has.
      failed: aCount,
    });
    const wrong = await start(`Bearer ${randomBytes(32).toString('hex')}`);
    expect(wrong.status).toBe(401);
    expect(await wrong.json()).toMatchObject({ reason: 'JOB_TOKEN_INVALID' });
    expect((await start()).status).toBe(401);
  });

  it('runs nothing on a server with no jobs token', async () => {
    const off = createApp({ ...deps, jobs: { ...deps.jobs, isScheduler: undefined } });
    const ran = await off.request('/jobs/daily-progress-push', {
      method: 'POST',
      headers: { authorization: `Bearer ${JOBS_TOKEN}` },
    });
    expect(ran.status).toBe(503);
    expect(await ran.json()).toMatchObject({ reason: 'JOBS_OFF' });
  });
});
