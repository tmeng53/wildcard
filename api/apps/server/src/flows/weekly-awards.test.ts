import { randomBytes, randomUUID } from 'node:crypto';

import {
  CheckInId,
  MemberId as CheckInMember,
  SquadId as CheckInSquad,
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresReplyStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
  type CheckInRecord,
} from '@wildcard/check-ins';
import {
  MemberId as MembersMember,
  createMembers,
  createPostgresProfileStore,
} from '@wildcard/members';
import { DeviceToken, MemberId as PushMember, type PushNotification } from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import {
  createPostgresAwardsStore,
  createWeeklyAwards,
  type LanguageModel,
} from '@wildcard/weekly-awards';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import { PhotoPath } from '../ports.js';
import {
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { unlimitedPublicRoutes } from '../test-kit/public-routes.js';

// The weekly awards end to end on local Supabase: check-ins, squads, members, photos and the
// awards table are real; the model answers what each test sets, and the push sender records
// what it would send.
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
const checkInStore = createPostgresCheckInStore(db);
const reactions = createPostgresReactionStore(db);
const checkIns = createCheckIns({
  store: checkInStore,
  membership: squads,
  reactions,
  replies: createPostgresReplyStore(db),
  plans: createPostgresWeeklyPlanStore(db),
  photos,
  calendarOf: memberCalendar(members),
  clock: () => new Date(),
});

const JOBS_TOKEN = randomBytes(32).toString('hex');
const RunBody = z.strictObject({
  version: z.literal(1),
  weeks: z.array(z.string()),
  squads: z.number(),
  given: z.number(),
  failed: z.number(),
  told: z.number(),
});

// The week of Monday 2026-10-19; its awards are on Sunday 10-25 at 8pm in New York.
const WEEK = '2026-10-19';
const AWARDS_AT = new Date('2026-10-26T00:00:00.000Z');
const HOUR = 3_600_000;

/** The members' letters in a prompt. */
const lettersIn = (prompt: string) =>
  z
    .object({ members: z.array(z.object({ member: z.string() })) })
    .parse(JSON.parse(prompt))
    .members.map(({ member }) => member);

/** The model's answer for a squad's members by letter, one title each. */
const titlesFor = (letters: readonly string[]) => ({
  version: 1,
  awards: letters.map((letter, index) => ({
    member: letter,
    titles: [{ title: `狠人${String(index)}号`, speech: '周三下着雨还去跑了。', move: 'pump' }],
  })),
});

function setup(options: { answer?: (prompt: string) => Promise<unknown> } = {}) {
  let now = new Date(AWARDS_AT.getTime() + HOUR);
  const prompts: string[] = [];
  const model: LanguageModel = {
    answer: async ({ prompt, reply }) => {
      prompts.push(prompt);
      const letters = lettersIn(prompt);
      const answer = options.answer ?? (() => Promise.resolve(titlesFor(letters)));
      return reply.parse(await answer(prompt));
    },
  };
  const sent: { token: string; notification: PushNotification }[] = [];
  const push = pushOn(db, {
    send: (device, notification) => {
      sent.push({ token: device.token, notification });
      return Promise.resolve('sent');
    },
  });
  const awards = createWeeklyAwards({ model, store: createPostgresAwardsStore(db) });
  const clock = () => now;
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
    weeklyAwards: { awards, clock },
    aiConsent: aiConsentOn(db),
    log: createLog(() => undefined),
    jobs: { ...noJobs, token: JOBS_TOKEN },
    admin: adminOn(),
  });
  const read = async ({
    token,
    squad,
    week = WEEK,
  }: {
    readonly token: string;
    readonly squad: string;
    readonly week?: string;
  }) => {
    const response = await app.request(`/squads/${squad}/weeks/${week}/story`, {
      headers: { authorization: `Bearer ${token}` },
    });
    return {
      status: response.status,
      body: z.record(z.string(), z.unknown()).parse(await response.json()),
    };
  };
  const nudge = async ({ token, squad }: { readonly token: string; readonly squad: string }) => {
    const response = await app.request(`/squads/${squad}/weeks/${WEEK}/story/nudge`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}` },
    });
    return response.status;
  };
  return {
    // As the scheduler starts it, every hour.
    run: async () => {
      const response = await app.request('/jobs/weekly-awards', {
        method: 'POST',
        headers: { authorization: `Bearer ${JOBS_TOKEN}` },
      });
      expect(response.status).toBe(200);
      return RunBody.parse(await response.json());
    },
    app,
    read,
    nudge,
    prompts,
    sent,
    at: (moment: Date) => {
      now = moment;
    },
  };
}

/** A signed-up member with a time zone and a phone. */
async function member(timeZone = 'America/Los_Angeles') {
  const signedUp = await signUp();
  await members.saveProfile({
    member: MembersMember.parse(signedUp.userId),
    profile: { timeZone, catchphrase: null, character: null },
  });
  const token = DeviceToken.parse(randomUUID().replaceAll('-', '').repeat(2));
  await pushOn(db).registerDevice({
    member: PushMember.parse(signedUp.userId),
    device: { token, environment: 'sandbox' },
  });
  return { ...signedUp, device: token };
}

async function squadOf(...joined: readonly { readonly userId: string }[]) {
  const id = randomUUID();
  const code = randomInviteCodes();
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${code})`.execute(
    db,
  );
  for (const [index, each] of joined.entries()) {
    const joinedAt = new Date(Date.UTC(2026, 9, 1, 0, index)).toISOString();
    await sql`insert into public.squad_members (squad_id, member_id, joined_at)
      values (${id}, ${each.userId}, ${joinedAt})`.execute(db);
  }
  return id;
}

/** A 练了 sent to the squad, saved as the app would have synced it. */
async function trained(
  author: { readonly userId: string },
  options: {
    squad: string;
    day?: string;
    createdAt?: Date;
    caption?: string;
    photos?: string[];
  },
) {
  const record: CheckInRecord = {
    id: CheckInId.parse(randomUUID()),
    member: CheckInMember.parse(author.userId),
    day: options.day ?? '2026-10-21',
    createdAt: options.createdAt ?? new Date('2026-10-21T14:00:00.000Z'),
    audience: [CheckInSquad.parse(options.squad)],
    kind: 'trained',
    training: {
      sport: 'run',
      ...(options.caption === undefined ? {} : { caption: options.caption }),
      ...(options.photos === undefined
        ? {}
        : { photos: options.photos.map((path) => ({ path: PhotoPath.parse(path) })) }),
    },
  };
  expect(await checkInStore.insert(record)).toStrictEqual({ saved: true });
  return record.id;
}

async function uploadedPhoto(owner: { readonly userId: string }) {
  const path = PhotoPath.parse(`${owner.userId}/${randomUUID()}`);
  const put = await fetch(await photos.createUploadUrl(path), {
    method: 'PUT',
    headers: { 'content-type': 'image/jpeg' },
    body: 'JPEG',
  });
  expect(put.ok).toBe(true);
  return path;
}

const Story = z.object({
  status: z.string(),
  squad: z.object({ id: z.string(), name: z.string() }),
  week: z.object({ from: z.string(), to: z.string() }),
  titles: z
    .array(
      z.object({
        member: z.string(),
        titles: z.array(z.object({ title: z.string(), speech: z.string(), move: z.string() })),
      }),
    )
    .optional(),
  hottest: z
    .object({
      checkIn: z.string(),
      day: z.string(),
      kind: z.string(),
      caption: z.string().optional(),
      photos: z.array(z.object({ path: z.string(), url: z.url() })),
      reactions: z.array(z.object({ kind: z.string(), label: z.string(), count: z.int() })),
    })
    .optional(),
});

describe('weekly awards', () => {
  it('runs only for the scheduler', async () => {
    const { app } = setup();
    const start = (authorization?: string) =>
      app.request('/jobs/weekly-awards', {
        method: 'POST',
        headers: authorization === undefined ? {} : { authorization },
      });
    const wrong = await start(`Bearer ${randomBytes(32).toString('hex')}`);
    expect(wrong.status).toBe(401);
    expect(await wrong.json()).toMatchObject({ reason: 'JOB_TOKEN_INVALID' });
    expect((await start()).status).toBe(401);
  });

  it('awards members who checked in before Sunday 8pm Eastern, and tells each once', async () => {
    const { run, read, sent, prompts } = setup();
    const [ana, bo, cy] = [await member(), await member('America/New_York'), await member()];
    const squad = await squadOf(ana, bo, cy);
    const photo = await uploadedPhoto(ana);
    // A caption no other squad has, to find this squad's prompt among the run's.
    const caption = `下雨也跑 ${randomUUID().slice(0, 8)}`;
    const top = await trained(ana, { squad, caption, photos: [photo] });
    await trained(bo, {
      squad,
      day: '2026-10-25',
      createdAt: new Date(AWARDS_AT.getTime() - 60_000),
    });
    // Cy's Sunday run is after the awards: it counts for the week, not for its awards.
    await trained(cy, {
      squad,
      day: '2026-10-25',
      createdAt: new Date(AWARDS_AT.getTime() + 60_000),
    });
    await reactions.save(top, {
      member: CheckInMember.parse(bo.userId),
      kind: 'cheer',
      reactedAt: new Date(),
    });

    const result = await run();
    expect(result.weeks).toStrictEqual(['2026-10-12', WEEK]);
    expect(prompts.filter((prompt) => prompt.includes(caption))).toHaveLength(1);
    const mine = sent.filter(({ token }) =>
      [ana.device, bo.device, cy.device].includes(DeviceToken.parse(token)),
    );
    expect(mine.map(({ token }) => token).toSorted()).toStrictEqual(
      [ana.device, bo.device].toSorted(),
    );
    expect(mine[0]?.notification).toStrictEqual({
      alert: { key: 'push.weeklyAwards.ready' },
      category: 'weeklyAwards',
      thread: 'weekly-awards',
      collapseId: `weekly-awards-${WEEK}`,
      interruption: 'active',
      event: { squad, weekStart: WEEK },
    });

    const { status, body } = await read({ token: cy.token, squad });
    expect(status).toBe(200);
    const forCy = Story.parse(body);
    expect(forCy.status).toBe('ready');
    expect(forCy.squad).toStrictEqual({ id: squad, name: 'squad' });
    expect(forCy.week).toStrictEqual({ from: WEEK, to: '2026-10-25' });
    expect(forCy.titles?.map((each) => each.member)).toStrictEqual([ana.userId, bo.userId]);
    expect(forCy.titles?.[0]?.titles).toStrictEqual([
      { title: '狠人0号', speech: '周三下着雨还去跑了。', move: 'pump' },
    ]);
    // Cy's only check-in came after the awards: nothing of theirs is hottest.
    expect(forCy.hottest).toBeUndefined();

    const forAna = Story.parse((await read({ token: ana.token, squad })).body);
    expect(forAna.hottest?.checkIn).toBe(top);
    expect(forAna.hottest?.caption).toBe(caption);
    expect(forAna.hottest?.reactions).toStrictEqual([{ kind: 'cheer', label: '加油', count: 1 }]);
    const view = forAna.hottest?.photos[0];
    expect(view?.path).toBe(photo);
    expect((await fetch(view?.url ?? '')).ok).toBe(true);
    // Bo's check-in had no reactions.
    expect(Story.parse((await read({ token: bo.token, squad })).body).hottest).toBeUndefined();

    // The next hourly run tells nobody again and asks the model nothing.
    const before = { sent: mine.length, prompts: prompts.length };
    await run();
    expect(sent.filter(({ token }) => token === ana.device)).toHaveLength(1);
    expect(prompts.filter((prompt) => prompt.includes(caption))).toHaveLength(1);
    expect(before.sent).toBe(2);
  });

  it('is not there before Sunday 8pm Eastern, waits only for its titles while the model fails, then is ready', async () => {
    let down = true;
    const { run, read, nudge, at, sent } = setup({
      answer: (prompt) => {
        if (down) return Promise.reject(new Error('down'));
        return Promise.resolve(titlesFor(lettersIn(prompt)));
      },
    });
    const [ana, bo] = [await member(), await member()];
    const squad = await squadOf(ana, bo);
    const top = await trained(ana, { squad });
    await reactions.save(top, {
      member: CheckInMember.parse(bo.userId),
      kind: 'lol',
      reactedAt: new Date(),
    });

    at(new Date(AWARDS_AT.getTime() - 60_000));
    const early = await read({ token: ana.token, squad });
    expect([early.status, early.body.reason]).toStrictEqual([404, 'WEEK_STORY_NOT_READY']);
    expect(await nudge({ token: ana.token, squad })).toBe(404);

    at(new Date(AWARDS_AT.getTime() + HOUR));
    expect((await run()).failed).toBeGreaterThanOrEqual(1);
    const pending = Story.parse((await read({ token: ana.token, squad })).body);
    expect([pending.status, pending.titles, pending.hottest?.checkIn]).toStrictEqual([
      'pending',
      undefined,
      top,
    ]);
    expect(pending.hottest?.reactions).toStrictEqual([{ kind: 'lol', label: '笑死', count: 1 }]);
    expect(sent.filter(({ token }) => token === ana.device)).toHaveLength(0);

    // 催一下主办方: the first nudge tells each admin which squad, how many tries failed and why.
    const admin = await member();
    await sql`insert into public.admins (member_id) values (${admin.userId})`.execute(db);
    const toAdmin = () => sent.filter(({ token }) => token === admin.device);
    expect(await nudge({ token: ana.token, squad })).toBe(204);
    expect(await nudge({ token: bo.token, squad })).toBe(204);
    expect(toAdmin().map(({ notification }) => notification)).toStrictEqual([
      {
        alert: { key: 'push.weeklyAwards.stuck', args: ['squad', '1', 'Error'] },
        category: 'weeklyAwardsStuck',
        thread: 'weekly-awards-stuck',
        collapseId: `weekly-awards-stuck-${squad}-${WEEK}`,
        interruption: 'active',
        event: { squad, weekStart: WEEK },
      },
    ]);

    down = false;
    at(new Date(AWARDS_AT.getTime() + 2 * HOUR));
    await run();
    const ready = Story.parse((await read({ token: ana.token, squad })).body);
    expect([ready.status, ready.titles?.length, ready.hottest?.checkIn]).toStrictEqual([
      'ready',
      1,
      top,
    ]);
    expect(sent.filter(({ token }) => token === ana.device)).toHaveLength(1);
    expect(await nudge({ token: ana.token, squad })).toBe(204);
    expect(toAdmin()).toHaveLength(1);
  });

  it('tells the admins of a nudge before the run has tried the squad', async () => {
    const { nudge, sent } = setup();
    const [ana, admin] = [await member(), await member()];
    await sql`insert into public.admins (member_id) values (${admin.userId})`.execute(db);
    const squad = await squadOf(ana);
    await trained(ana, { squad });
    expect(await nudge({ token: ana.token, squad })).toBe(204);
    expect(
      sent
        .filter(({ token }) => token === admin.device)
        .map(({ notification }) => notification.alert),
    ).toStrictEqual([{ key: 'push.weeklyAwards.stuck', args: ['squad', '0', '-'] }]);
  });

  it('is ready with nobody on it when the squad didn’t check in, and only for its members', async () => {
    const { read, nudge } = setup();
    const [ana, stranger] = [await member(), await member()];
    const squad = await squadOf(ana);
    const empty = Story.parse((await read({ token: ana.token, squad })).body);
    expect([empty.status, empty.titles]).toStrictEqual(['ready', []]);
    const refused = await read({ token: stranger.token, squad });
    expect([refused.status, refused.body.reason]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
    expect((await read({ token: ana.token, squad, week: '2026-10-20' })).status).toBe(400);
    expect(await nudge({ token: stranger.token, squad })).toBe(403);
    // Nothing to wait for, so nobody to tell.
    expect(await nudge({ token: ana.token, squad })).toBe(204);
    expect(
      (
        await sql<{ n: number }>`select count(*)::int as n from public.weekly_awards
        where squad_id = ${squad}`.execute(db)
      ).rows[0]?.n,
    ).toBe(0);
  });

  it('leaves out a member who left the squad', async () => {
    const { run, read } = setup();
    const [ana, bo] = [await member(), await member()];
    const squad = await squadOf(ana, bo);
    await trained(ana, { squad });
    await trained(bo, { squad });
    await run();
    expect(Story.parse((await read({ token: ana.token, squad })).body).titles).toHaveLength(2);
    await sql`delete from public.squad_members where squad_id = ${squad} and member_id = ${bo.userId}`.execute(
      db,
    );
    const left = Story.parse((await read({ token: ana.token, squad })).body);
    expect(left.titles?.map((each) => each.member)).toStrictEqual([ana.userId]);
  });

  it('keeps trying a squad still failing into the next week', async () => {
    let down = true;
    const { run, read, at } = setup({
      answer: (prompt) =>
        down ? Promise.reject(new Error('down')) : Promise.resolve(titlesFor(lettersIn(prompt))),
    });
    const ana = await member();
    const squad = await squadOf(ana);
    await trained(ana, { squad });
    await run();
    expect(Story.parse((await read({ token: ana.token, squad })).body).status).toBe('pending');
    down = false;
    at(new Date(AWARDS_AT.getTime() + 7 * 24 * HOUR + HOUR));
    await run();
    expect(Story.parse((await read({ token: ana.token, squad })).body).status).toBe('ready');
  });
});
