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
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import { adminOn, aiConsentOn, config, pushOn, signUp } from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import { unusedWeekSummaryWords, unusedWeeklyAwards } from '../test-kit/weekly-awards.js';
import {
  dailyProgressNotification,
  reactionInteractions,
  sendDailyProgress,
  type InteractionSource,
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
const pokes = new Map<string, Set<string>>();
/** A stand-in for an interaction that isn't built yet: pokes, from `pokes`. */
const pokeSource: InteractionSource = ({ member }) =>
  Promise.resolve(new Map([['poke', pokes.get(member) ?? new Set<string>()]]));
const interactions = [reactionInteractions(checkIns), pokeSource];

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
  jobs: { token: JOBS_TOKEN, interactions, clock: () => new Date() },
  admin: adminOn(),
  publicRoutes: unlimitedPublicRoutes,
  aiConsent: aiConsentOn(db),
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

/** A member with a profile in `at`'s zone and a phone. */
async function member(at: { readonly zone: string; readonly offset: number }) {
  const signedUp = await signUp();
  const saved = await call('PUT', {
    path: '/me/profile',
    token: signedUp.token,
    body: { version: 1, timeZone: at.zone },
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

  it('counts any source’s interactions with the reactions, and one alone is worth a push', async () => {
    const [eve, mate] = [await member(evening), await member(morning)];
    await squadOf(eve, mate);
    pokes.set(eve.userId, new Set([mate.userId]));
    await run();
    expect(sentTo.get(eve.phone)).toMatchObject([
      {
        alert: { key: 'push.dailyProgress.received', args: ['0', '10', '1'] },
        event: { received: { poke: 1 } },
      },
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
      }),
    ).toMatchObject({
      alert: { key: 'push.dailyProgress', args: ['14', '22'] },
      event: { received: { reaction: 0 } },
    });
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
    const off = createApp({ ...deps, jobs: { ...deps.jobs, token: undefined } });
    const ran = await off.request('/jobs/daily-progress-push', {
      method: 'POST',
      headers: { authorization: `Bearer ${JOBS_TOKEN}` },
    });
    expect(ran.status).toBe(503);
    expect(await ran.json()).toMatchObject({ reason: 'JOBS_OFF' });
  });
});
