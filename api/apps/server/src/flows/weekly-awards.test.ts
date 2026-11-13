import { randomBytes, randomUUID } from 'node:crypto';

import { AI_CONSENT_COPY_VERSION, MemberId as ConsentMember } from '@wildcard/ai-consent';
import {
  CheckInId,
  MemberId as CheckInMember,
  SquadId as CheckInSquad,
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
  Emoji,
  type CheckInRecord,
} from '@wildcard/check-ins';
import {
  MemberId as MembersMember,
  createMembers,
  createPostgresProfileStore,
} from '@wildcard/members';
import {
  createNotices,
  createPostgresNoticeStore,
  createPostgresBroadcastStore,
} from '@wildcard/notices';
import { DeviceToken, MemberId as PushMember, type PushNotification } from '@wildcard/push';
import {
  createPostgresSquadStore,
  createSquads,
  MemberId as SquadsMember,
  randomInviteCodes,
  SquadId as SquadsSquad,
} from '@wildcard/squads';
import {
  createPostgresAwardSettings,
  createPostgresAwardsStore,
  createPostgresWeekStoryStore,
  createWeeklyAwards,
} from '@wildcard/weekly-awards';
import type { LanguageModel } from '@wildcard/language-model';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { jobsTokenScheduler } from '../adapters/scheduler.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import { PhotoPath } from '../ports.js';
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
  weatherOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import {
  unusedCoachHiring,
  unusedCoachActivity,
  unusedCoachLetters,
  unusedUnlocks,
  unusedGifts,
  noRewards,
  ignoredNotices,
  unusedFeedback,
} from '../test-kit/weekly-awards.js';

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
const aiConsent = aiConsentOn(db);
const checkInStore = createPostgresCheckInStore(db);
const reactions = createPostgresReactionStore(db);
const comments = createPostgresCommentStore(db);
const checkIns = createCheckIns({
  sports: createSports({ store: createPostgresSportStore(db) }),
  store: checkInStore,
  membership: squads,
  reactions,
  comments,
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
  goals: z.object({ week: z.string(), suggested: z.number(), failed: z.number() }),
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
  awards: Object.fromEntries(
    letters.map((letter, index) => [
      letter,
      [
        {
          title: `狠人${String(index)}号`,
          speech: '周三下着雨还去跑了。',
          move: 'pump',
          badge: { shape: 'circle', colour: 'gym', glyph: 'flame.fill' },
        },
      ],
    ]),
  ),
  ending: { headline: '稳了', line: '三天全拿下，计划都不够用。' },
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
  const awards = createWeeklyAwards({
    model,
    settings: createPostgresAwardSettings(db),
    store: createPostgresAwardsStore(db),
    stories: createPostgresWeekStoryStore(db),
    aiConsented: (members) =>
      aiConsent.currentAmong(members.map((member) => ConsentMember.parse(member))),
    memes: () => Promise.resolve([]),
    sportGlyphs: () => Promise.resolve([]),
  });
  const clock = () => now;
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
    checkIns,
    weeklyPlans: createWeeklyPlans({
      sports: createSports({ store: createPostgresSportStore(db) }),
      store: createPostgresWeeklyPlanStore(db),
      calendarOf: memberCalendar(members),
      clock: () => new Date(),
    }),
    members,
    squads,
    push,
    disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
    scenes: scenesOn(db),
    switches: switchesOn(db),
    weeklyAwards: { awards, clock },
    unlocks: unusedUnlocks,
    gifts: unusedGifts,
    rewards: noRewards,
    coachHiring: unusedCoachHiring,
    coachActivity: unusedCoachActivity,
    coachLetters: unusedCoachLetters,
    notices: createNotices({
      store: createPostgresNoticeStore(db),
      broadcasts: createPostgresBroadcastStore(db),
      clock: () => new Date(),
    }),
    coachNames: () => Promise.reject(new Error('unused')),
    liveEvents: ignoredNotices.liveEvents,
    aiConsent,
    nudges: nudgesOn(db),
    ...placesOn(db),
    savedPlaces: savedPlacesOn(db),
    weather: weatherOn(db),
    ...unusedFeedback,
    log: createLog(() => undefined),
    jobs: { ...noJobs, isScheduler: jobsTokenScheduler(JOBS_TOKEN) },
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
  const weeks = async ({ token, squad }: { readonly token: string; readonly squad: string }) => {
    const response = await app.request(`/squads/${squad}/stories`, {
      headers: { authorization: `Bearer ${token}` },
    });
    return {
      status: response.status,
      body: z.record(z.string(), z.unknown()).parse(await response.json()),
    };
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
    weeks,
    prompts,
    sent,
    at: (moment: Date) => {
      now = moment;
    },
  };
}

/** A signed-up member with a time zone and a phone, who agreed to AI use unless told not. */
async function member(timeZone = 'America/Los_Angeles', agreedToAi = true) {
  const signedUp = await signUp();
  if (agreedToAi) {
    await aiConsent.give({
      member: ConsentMember.parse(signedUp.userId),
      copyVersion: AI_CONSENT_COPY_VERSION,
    });
  }
  await members.saveProfile({
    member: MembersMember.parse(signedUp.userId),
    profile: { timeZone, catchphrase: null, character: null, jerseyNumber: null },
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
    await joinAt({ squad: id, who: each, moment: new Date(Date.UTC(2026, 9, 1, 0, index)) });
  }
  return id;
}

/** `who` joins the squad at `moment`, logged as the squads module logs a join. */
async function joinAt({
  squad,
  who,
  moment,
}: {
  readonly squad: string;
  readonly who: { readonly userId: string };
  readonly moment: Date;
}) {
  const at = moment.toISOString();
  await sql`insert into public.squad_members (squad_id, member_id, joined_at)
    values (${squad}, ${who.userId}, ${at})`.execute(db);
  await sql`insert into public.squad_membership_events (squad_id, member_id, kind, at)
    values (${squad}, ${who.userId}, 'joined', ${at})`.execute(db);
}

/** A reaction left before the awards, so they count it. */
const BEFORE_AWARDS = new Date(AWARDS_AT.getTime() - HOUR);

/** A 练了 sent to the squad, saved as the app would have synced it. */
async function trained(
  author: { readonly userId: string },
  options: {
    squad: string;
    day?: string;
    createdAt?: Date;
    caption?: string;
    photos?: string[];
    minutes?: number;
  },
) {
  const record: CheckInRecord = {
    id: CheckInId.parse(randomUUID()),
    member: CheckInMember.parse(author.userId),
    day: options.day ?? '2026-10-21',
    createdAt: options.createdAt ?? new Date('2026-10-21T14:00:00.000Z'),
    inFeed: true,
    audience: [CheckInSquad.parse(options.squad)],
    kind: 'trained',
    training: {
      sport: 'run',
      ...(options.minutes === undefined ? {} : { minutes: options.minutes }),
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
  stuck: z.literal(true).optional(),
  squad: z.object({ id: z.string(), name: z.string() }),
  week: z.object({ from: z.string(), to: z.string() }),
  scene: z.string(),
  members: z.array(z.object({ member: z.string() })),
  podium: z
    .object({ champion: z.string(), sides: z.array(z.string()), planDone: z.array(z.string()) })
    .optional(),
  myWeek: z
    .object({
      plannedDays: z.int(),
      trainedDays: z.int(),
      days: z.array(z.object({ day: z.string(), kind: z.string(), sport: z.string().optional() })),
      reactionsReceived: z.int(),
    })
    .optional(),
  squadWeek: z
    .object({
      members: z.array(
        z.object({
          member: z.string(),
          trainedDays: z.int(),
          days: z.array(
            z.object({
              kind: z.string(),
              sport: z.string().optional(),
              minutes: z.int().optional(),
            }),
          ),
          reactionsReceived: z.int(),
        }),
      ),
    })
    .optional(),
  meals: z.unknown().optional(),
  bestDisclaimer: z.unknown().optional(),
  ending: z
    .object({
      done: z.int(),
      plan: z.int(),
      headline: z.string().optional(),
      line: z.string().optional(),
    })
    .optional(),
  titles: z
    .array(
      z.object({
        member: z.string(),
        titles: z.array(
          z.strictObject({
            title: z.string(),
            speech: z.string(),
            move: z.string(),
            badge: z
              .strictObject({
                shape: z.string(),
                colour: z.string(),
                tone: z.string().optional(),
                glyph: z.string(),
              })
              .optional(),
          }),
        ),
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
      reactions: z.array(z.object({ emoji: z.string(), count: z.int() })),
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

  it('awards members who checked in before Sunday 8pm Eastern, and tells the whole squad once', async () => {
    const { run, read, sent, prompts, app } = setup();
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
      emoji: Emoji.parse('❤️'),
      reactedAt: BEFORE_AWARDS,
    });

    const result = await run();
    // An hour after Sunday 8pm in New York it is Monday in the zones furthest ahead.
    expect(result.weeks).toStrictEqual(['2026-10-05', '2026-10-12', WEEK]);
    expect(prompts.filter((prompt) => prompt.includes(caption))).toHaveLength(1);
    const mine = sent.filter(({ token }) =>
      [ana.device, bo.device, cy.device].includes(DeviceToken.parse(token)),
    );
    // Everyone in the squad hears the 战报 is ready, Cy too, who won nothing.
    expect(mine.map(({ token }) => token).toSorted()).toStrictEqual(
      [ana.device, bo.device, cy.device].toSorted(),
    );
    expect(mine[0]?.notification).toStrictEqual({
      alert: { key: 'push.weeklyAwards.ready' },
      category: 'weeklyAwards',
      thread: 'weekly-awards',
      collapseId: `weekly-awards-${WEEK}`,
      interruption: 'active',
      event: { squad, weekStart: WEEK },
    });
    // Everyone in the squad finds it in 通知 too, once, Cy included.
    const noticesOf = async (token: string) =>
      z
        .object({ notices: z.array(z.record(z.string(), z.unknown())) })
        .parse(
          await (
            await app.request('/me/notices', { headers: { authorization: `Bearer ${token}` } })
          ).json(),
        )
        .notices.map(({ kind, squadId, alert, weekStart }) => ({
          kind,
          squadId,
          alert,
          weekStart,
        }));
    const readyNotice = {
      kind: 'weeklyAwards',
      squadId: squad,
      alert: { key: 'push.weeklyAwards.ready', args: [] },
      weekStart: WEEK,
    };
    expect(await noticesOf(ana.token)).toStrictEqual([readyNotice]);
    expect(await noticesOf(cy.token)).toStrictEqual([readyNotice]);

    const { status, body } = await read({ token: cy.token, squad });
    expect(status).toBe(200);
    const forCy = Story.parse(body);
    expect(forCy.status).toBe('ready');
    expect(forCy.squad).toStrictEqual({ id: squad, name: 'squad' });
    expect(forCy.week).toStrictEqual({ from: WEEK, to: '2026-10-25' });
    expect(forCy.titles?.map((each) => each.member)).toStrictEqual([ana.userId, bo.userId]);
    // Each title comes with its badge as the badge board draws it, in its colour's tone.
    expect(forCy.titles?.[0]?.titles).toStrictEqual([
      {
        title: '狠人0号',
        speech: '周三下着雨还去跑了。',
        move: 'pump',
        badge: { shape: 'circle', colour: 'gym', tone: '#4A6C8C', glyph: 'flame.fill' },
      },
    ]);
    // Cy's only check-in came after the awards: nothing of theirs is hottest.
    expect(forCy.hottest).toBeUndefined();

    const forAna = Story.parse((await read({ token: ana.token, squad })).body);
    expect(forAna.hottest?.checkIn).toBe(top);
    expect(forAna.hottest?.caption).toBe(caption);
    expect(forAna.hottest?.reactions).toStrictEqual([{ emoji: '❤️', count: 1 }]);
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
    expect(before.sent).toBe(3);

    // Ana edits her hottest post, taking its photo off: the story keeps its words and reactions
    // as frozen at the awards, but never shows the photo gone from Storage.
    const edited = `改了 ${randomUUID().slice(0, 8)}`;
    await checkIns.edit({
      id: CheckInId.parse(top),
      member: CheckInMember.parse(ana.userId),
      edit: { version: 1, kind: 'trained', training: { sport: 'run', caption: edited } },
    });
    const afterEdit = Story.parse((await read({ token: ana.token, squad })).body);
    expect(afterEdit.hottest?.caption).toBe(caption);
    expect(afterEdit.hottest?.photos).toStrictEqual([]);
    expect(afterEdit.hottest?.reactions).toStrictEqual([{ emoji: '❤️', count: 1 }]);

    // Ana deletes her hottest post: her titles stay, the post leaves her story.
    await checkIns.delete({
      id: CheckInId.parse(top),
      member: CheckInMember.parse(ana.userId),
    });
    const afterDelete = Story.parse((await read({ token: ana.token, squad })).body);
    expect(afterDelete.titles?.[0]?.titles).toStrictEqual(forCy.titles?.[0]?.titles);
    expect(afterDelete.hottest).toBeUndefined();
  });

  it('ends a squad’s week at Sunday 8pm in its own time zone', async () => {
    const { run, read, at, sent } = setup();
    const [ana, bo] = [await member('Asia/Taipei'), await member('America/New_York')];
    const taipei = await squadOf(ana);
    const newYork = await squadOf(bo);
    await sql`insert into public.squad_time_zones (squad_id, time_zone, week_start)
      values (${taipei}, 'Asia/Taipei', '2026-10-12')`.execute(db);
    await trained(ana, { squad: taipei });
    await trained(bo, { squad: newYork });

    // Sunday 9pm in Taipei is Sunday 9am in New York.
    at(new Date('2026-10-25T13:00:00.000Z'));
    expect(Story.parse((await read({ token: ana.token, squad: taipei })).body).squad.id).toBe(
      taipei,
    );
    const early = await read({ token: bo.token, squad: newYork });
    expect([early.status, early.body.reason]).toStrictEqual([404, 'WEEK_STORY_NOT_READY']);
    await run();
    expect(sent.filter(({ token }) => token === ana.device)).toHaveLength(1);
    expect(sent.filter(({ token }) => token === bo.device)).toHaveLength(0);

    at(new Date(AWARDS_AT.getTime() + HOUR));
    await run();
    expect(sent.filter(({ token }) => token === ana.device)).toHaveLength(1);
    expect(sent.filter(({ token }) => token === bo.device)).toHaveLength(1);
  });

  it('gives no awards, and asks no model, for a squad everyone left', async () => {
    const { run, prompts } = setup();
    const [ana, bo] = [await member(), await member()];
    const squad = await squadOf(ana, bo);
    const caption = `走光了 ${randomUUID().slice(0, 8)}`;
    await trained(ana, { squad, caption });
    await squads.leave({ squad: SquadsSquad.parse(squad), member: SquadsMember.parse(ana.userId) });
    await squads.leave({ squad: SquadsSquad.parse(squad), member: SquadsMember.parse(bo.userId) });

    await run();
    expect(prompts.some((prompt) => prompt.includes(caption))).toBe(false);
    const { rows } = await sql`select 1 from public.week_stories where squad_id = ${squad}`.execute(
      db,
    );
    expect(rows).toHaveLength(0);
  });

  it('leaves out of the prompt and the awards a member who hasn’t agreed to AI use', async () => {
    const { run, read, sent, prompts } = setup();
    const [ana, bo] = [await member(), await member('America/Los_Angeles', false)];
    const squad = await squadOf(ana, bo);
    const caption = `只给同意的人 ${randomUUID().slice(0, 8)}`;
    await trained(ana, { squad, caption });
    const boCaption = `没同意 ${randomUUID().slice(0, 8)}`;
    await trained(bo, { squad, caption: boCaption });

    await run();
    const mine = prompts.filter((prompt) => prompt.includes(caption));
    expect(mine).toHaveLength(1);
    expect(lettersIn(mine[0] ?? '')).toStrictEqual(['A']);
    expect(prompts.some((prompt) => prompt.includes(boCaption))).toBe(false);
    const story = Story.parse((await read({ token: bo.token, squad })).body);
    expect(story.titles?.map((each) => each.member)).toStrictEqual([ana.userId]);
    // Bo still hears the squad's 战报 is ready, though they won no titles.
    expect(sent.filter(({ token }) => token === bo.device)).toHaveLength(1);
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
      emoji: Emoji.parse('😂'),
      reactedAt: BEFORE_AWARDS,
    });

    at(new Date(AWARDS_AT.getTime() - 60_000));
    const early = await read({ token: ana.token, squad });
    expect([early.status, early.body.reason]).toStrictEqual([404, 'WEEK_STORY_NOT_READY']);
    expect(await nudge({ token: ana.token, squad })).toBe(404);

    at(new Date(AWARDS_AT.getTime() + HOUR));
    // Before the hourly run reaches the squad, the titles are only on their way.
    const waiting = Story.parse((await read({ token: ana.token, squad })).body);
    expect([waiting.status, waiting.stuck]).toStrictEqual(['pending', undefined]);
    expect((await run()).failed).toBeGreaterThanOrEqual(1);
    const pending = Story.parse((await read({ token: ana.token, squad })).body);
    expect(pending.stuck).toBe(true);
    // The page's words wait with the titles: the app says how far the squad got meanwhile.
    expect(pending.ending).toStrictEqual({ done: 1, plan: 6 });
    expect([pending.status, pending.titles, pending.hottest?.checkIn]).toStrictEqual([
      'pending',
      undefined,
      top,
    ]);
    expect(pending.hottest?.reactions).toStrictEqual([{ emoji: '😂', count: 1 }]);
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
    expect(empty.squadWeek).toBeUndefined();
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
    // A week with nothing to tell keeps no story, so asking for any past week stores nothing.
    expect(
      (
        await sql<{ n: number }>`select count(*)::int as n from public.week_stories
        where squad_id = ${squad}`.execute(db)
      ).rows[0]?.n,
    ).toBe(0);
  });

  it('lists the weeks the squad has a 战报 for, the latest first, freezing the one just out', async () => {
    const { weeks, at } = setup();
    const [ana, bo, stranger] = [await member(), await member(), await member()];
    const squad = await squadOf(ana, bo);
    const quiet = await squadOf(stranger);
    await trained(ana, {
      squad,
      day: '2026-10-14',
      createdAt: new Date('2026-10-14T14:00:00.000Z'),
    });
    await trained(bo, { squad, day: '2026-10-20' });

    // Before Sunday 8pm the week isn't out: only the week before, frozen as it is listed.
    at(new Date(AWARDS_AT.getTime() - 60_000));
    expect((await weeks({ token: ana.token, squad })).body.weeks).toStrictEqual([
      { weekStart: '2026-10-12' },
    ]);

    // From 8pm the week just out is listed, though no run or read froze it yet.
    at(new Date(AWARDS_AT.getTime() + 60_000));
    const listed = await weeks({ token: bo.token, squad });
    expect(listed).toStrictEqual({
      status: 200,
      body: { version: 1, weeks: [{ weekStart: WEEK }, { weekStart: '2026-10-12' }] },
    });
    // A squad that never checked in has none, and only members may ask.
    expect((await weeks({ token: stranger.token, squad: quiet })).body.weeks).toStrictEqual([]);
    const refused = await weeks({ token: stranger.token, squad });
    expect([refused.status, refused.body.reason]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
  });

  it('is frozen at the awards: later joins, leaves, check-ins and scenes don’t change it', async () => {
    const { run, read, at, prompts } = setup();
    const [ana, bo, cy] = [await member(), await member(), await member()];
    const squad = await squadOf(ana, bo);
    const top = await trained(ana, { squad, day: '2026-10-20', minutes: 45 });
    await trained(ana, { squad, day: '2026-10-21' });
    await trained(bo, { squad });
    await reactions.save(top, {
      member: CheckInMember.parse(bo.userId),
      emoji: Emoji.parse('💪'),
      reactedAt: BEFORE_AWARDS,
    });
    await run();
    const first = Story.parse((await read({ token: ana.token, squad })).body);
    expect(first.scene).toBe('gym');
    expect(first.members.map(({ member: id }) => id)).toStrictEqual([ana.userId, bo.userId]);
    expect(first.titles).toHaveLength(2);
    // 3 训练 against the squad's weekly goal: 人均 3 次 (the default) times its 2 members.
    expect(first.ending).toStrictEqual({
      done: 3,
      plan: 6,
      headline: '稳了',
      line: '三天全拿下，计划都不够用。',
    });
    // The run reads every squad that checked in that week; this one's prompt brings its 训练.
    expect(prompts.some((prompt) => prompt.includes('"squad":{"trainings":3,'))).toBe(true);
    // Ana trained the most days, so she stands in the middle; neither planned a day this week,
    // so both carry the plan-done mark.
    expect(first.podium).toStrictEqual({
      champion: ana.userId,
      sides: [bo.userId],
      planDone: [ana.userId, bo.userId],
    });
    expect(first.myWeek?.plannedDays).toBe(0);
    expect(first.myWeek?.days.map(({ kind }) => kind).slice(0, 3)).toStrictEqual([
      'none',
      'trained',
      'trained',
    ]);
    expect(first.hottest?.reactions).toStrictEqual([{ emoji: '💪', count: 1 }]);
    expect(
      first.squadWeek?.members.map(({ member: id, trainedDays, days, reactionsReceived }) => [
        id,
        trainedDays,
        days.map(({ minutes }) => minutes ?? 0),
        reactionsReceived,
      ]),
    ).toStrictEqual([
      [ana.userId, 2, [0, 45, 0, 0, 0, 0, 0], 1],
      [bo.userId, 1, [0, 0, 0, 0, 0, 0, 0], 0],
    ]);

    // After the awards: Cy joins, Bo leaves, Ana posts late, a reaction comes and the scene changes.
    at(new Date(AWARDS_AT.getTime() + 3 * HOUR));
    await joinAt({ squad, who: cy, moment: new Date() });
    await sql`delete from public.squad_members where squad_id = ${squad} and member_id = ${bo.userId}`.execute(
      db,
    );
    await sql`insert into public.squad_membership_events (squad_id, member_id, kind)
      values (${squad}, ${bo.userId}, 'left')`.execute(db);
    await trained(ana, { squad, day: '2026-10-25', createdAt: new Date() });
    await reactions.save(top, {
      member: CheckInMember.parse(cy.userId),
      emoji: Emoji.parse('🔥'),
      reactedAt: new Date(),
    });
    await sql`insert into public.squad_scene_picks (squad_id, week_start, scene)
      values (${squad}, ${WEEK}, 'pool')`.execute(db);
    await sql`update public.squads set name = 'renamed' where id = ${squad}`.execute(db);

    const later = Story.parse((await read({ token: ana.token, squad })).body);
    expect(later).toStrictEqual(first);
    // Cy can read the squad's story now, but isn't in it: they first show up next week.
    const forCy = Story.parse((await read({ token: cy.token, squad })).body);
    expect(forCy.members.map(({ member: id }) => id)).toStrictEqual([ana.userId, bo.userId]);
    expect(forCy.myWeek).toBeUndefined();
    expect(
      (
        await sql<{ n: number }>`select count(*)::int as n from public.week_story_members
        where squad_id = ${squad}`.execute(db)
      ).rows[0]?.n,
    ).toBe(2);
    await expect(
      sql`update public.week_stories set story = story where squad_id = ${squad}`.execute(db),
    ).rejects.toThrow(/frozen/u);
  });

  it('freezes on the first read when no run has, and drops a post deleted since', async () => {
    const { read, run } = setup();
    const [ana, bo] = [await member(), await member()];
    const squad = await squadOf(ana, bo);
    const top = await trained(ana, { squad });
    await reactions.save(top, {
      member: CheckInMember.parse(bo.userId),
      emoji: Emoji.parse('❤️'),
      reactedAt: BEFORE_AWARDS,
    });
    const first = Story.parse((await read({ token: ana.token, squad })).body);
    expect([first.status, first.hottest?.checkIn]).toStrictEqual(['pending', top]);
    await sql`delete from public.check_ins where id = ${top}`.execute(db);
    const after = Story.parse((await read({ token: ana.token, squad })).body);
    expect(after.hottest).toBeUndefined();
    // Its words and photos go with it, not only out of sight.
    expect(
      (
        await sql<{ n: number }>`select count(*)::int as n from public.week_story_posts
        where check_in_id = ${top}`.execute(db)
      ).rows[0]?.n,
    ).toBe(0);
    expect(after.myWeek?.trainedDays).toBe(1);
    // The next run finishes it, though no check-in of the week is left to find the squad by.
    await run();
    expect(Story.parse((await read({ token: ana.token, squad })).body).status).toBe('ready');
  });

  it('counts the plans as they stood at the awards, whenever it freezes', async () => {
    const { read } = setup();
    const ana = await member();
    const squad = await squadOf(ana);
    await sql`update public.profiles set created_at = '2026-10-01T00:00:00Z'
      where member_id = ${ana.userId}`.execute(db);
    await trained(ana, { squad });
    const train = JSON.stringify({
      version: 1,
      days: Array.from({ length: 7 }, () => ({ kind: 'train' })),
    });
    const restMost = JSON.stringify({
      version: 1,
      days: [{ kind: 'train' }, ...Array.from({ length: 6 }, () => ({ kind: 'rest' }))],
    });
    await sql`insert into public.plan_templates (member_id, from_week, payload, at)
      values (${ana.userId}, ${WEEK}, ${train}::jsonb, ${BEFORE_AWARDS})`.execute(db);
    // Changed after 8pm, before anyone read the 战报.
    await sql`insert into public.weekly_plans (member_id, week_start, payload)
      values (${ana.userId}, ${WEEK}, ${restMost}::jsonb)`.execute(db);
    await sql`insert into public.weekly_plan_events (member_id, week_start, payload, at)
      values (${ana.userId}, ${WEEK}, ${restMost}::jsonb,
        ${new Date(AWARDS_AT.getTime() + HOUR / 2)})`.execute(db);
    const story = Story.parse((await read({ token: ana.token, squad })).body);
    expect(story.myWeek?.plannedDays).toBe(7);
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
