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
  createCoachHiring,
  createPostgresCoachCatalog,
  createPostgresCoachHiring,
} from '@wildcard/coach';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import {
  createPostgresAwardSettings,
  createPostgresAwardsStore,
  createPostgresWeekStoryStore,
  createWeeklyAwards,
} from '@wildcard/weekly-awards';
import {
  createNotices,
  createPostgresNoticeStore,
  createPostgresBroadcastStore,
} from '@wildcard/notices';
import {
  MemberId as RewardMember,
  createPostgresRewardStore,
  createPostgresUnlockStore,
  createRewards,
} from '@wildcard/unlocks';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createMemoryRateLimit } from '../adapters/memory-rate-limit.js';
import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import {
  adminOn,
  aiConsentOn,
  alsoJoinedEarlier,
  config,
  scenesOn,
  switchesOn,
  noJobs,
  nudgesOn,
  weatherOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import {
  ignoredNotices,
  unusedCoachActivity,
  unusedCoachLetters,
  unusedUnlocks,
  unusedGifts,
  unusedWeekSummaryWords,
  unusedFeedback,
} from '../test-kit/weekly-awards.js';
import { catalogOn } from '../test-kit/public-routes.js';

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const rewards = createRewards({
  store: createPostgresRewardStore(db),
  unlocks: createPostgresUnlockStore(db),
  clock: () => new Date(),
});
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
  publicRoutes: {
    proxyHops: 1,
    inviteLookups: createMemoryRateLimit({ limit: 3, windowSeconds: 600, clock: () => new Date() }),
    catalogReads: () => ({ allowed: true }),
  },
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
  scenes: scenesOn(db),
  switches: switchesOn(db),
  push: pushOn(db),
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  aiConsent: aiConsentOn(db),
  nudges: nudgesOn(db),
  weather: weatherOn(db),
  ...unusedFeedback,
  weeklyAwards: {
    awards: createWeeklyAwards({
      model: { answer: () => Promise.reject(new Error('unused')) },
      settings: createPostgresAwardSettings(db),
      store: createPostgresAwardsStore(db),
      stories: createPostgresWeekStoryStore(db),
      aiConsented: (all) => Promise.resolve(all),
      memes: () => Promise.resolve([]),
      sportGlyphs: () => Promise.resolve([]),
    }),
    clock: () => new Date(),
  },
  weekSummaryWords: unusedWeekSummaryWords,
  unlocks: unusedUnlocks,
  gifts: unusedGifts,
  rewards,
  coachActivity: unusedCoachActivity,
  coachLetters: unusedCoachLetters,
  notices: createNotices({
    store: createPostgresNoticeStore(db),
    broadcasts: createPostgresBroadcastStore(db),
    clock: () => new Date(),
  }),
  coachNames: () => Promise.reject(new Error('unused')),
  liveEvents: ignoredNotices.liveEvents,
  coachHiring: createCoachHiring({
    hiring: createPostgresCoachHiring(db),
    catalog: createPostgresCoachCatalog(db),
  }),
  log: createLog(() => undefined),
  jobs: noJobs,
  admin: adminOn(),
});

async function call({
  method,
  path,
  token,
  body,
}: {
  readonly method: string;
  readonly path: string;
  readonly token?: string | undefined;
  readonly body?: unknown;
}) {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  const response = await app.request(path, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  return {
    status: response.status,
    type: response.headers.get('content-type'),
    body: text === '' ? undefined : z.unknown().parse(JSON.parse(text)),
  };
}

const SquadBody = z.object({ id: z.uuid(), inviteCode: z.string() });

/** A squad `captain` made, with `others` in it too. */
async function squadOf(captain: { token: string }, ...others: { token: string }[]) {
  const made = await call({
    method: 'PUT',
    path: `/squads/${randomUUID()}`,
    token: captain.token,
    body: { version: 1, name: '早八跑团' },
  });
  expect(made.status).toBe(201);
  const squad = SquadBody.parse(made.body);
  for (const other of others) {
    const joined = await call({
      method: 'POST',
      path: `/squad-invites/${squad.inviteCode}/accept`,
      token: other.token,
    });
    expect(joined.status).toBe(201);
  }
  return squad.id;
}

const reason = (response: { readonly body?: unknown }) =>
  z.object({ reason: z.string() }).safeParse(response.body).data?.reason;

const look = { persona: 'deadpan', variants: { body: 'peach', hair: 'ponytail' }, colors: {} };

/** Saves a member's profile with a character, as the app does right after signing up. */
async function profileOf(
  member: { token: string },
  { nickname, jerseyNumber }: { nickname: string; jerseyNumber?: number },
) {
  const saved = await call({
    method: 'PUT',
    path: '/me/profile',
    token: member.token,
    body: {
      version: 1,
      timeZone: 'UTC',
      catchphrase: null,
      character: { nickname, look },
      ...(jerseyNumber === undefined ? {} : { jerseyNumber }),
    },
  });
  expect(saved.status).toBe(200);
}

const shield = { shape: 'shield', colour: 'track', glyph: 'sun.max.fill' };
const hexagon = { shape: 'hexagon', colour: 'pool', glyph: 'snowflake' };
// The badges as the API shows them, with their colours' tones from the catalog.
const shownShield = { ...shield, tone: '#E65345' };
const shownHexagon = { ...hexagon, tone: '#079BB8' };

/** Freezes a squad's 战报 for a week under the name it had then, as Sunday 8pm does. */
async function freeze({
  squad,
  weekStart,
  name,
}: {
  squad: string;
  weekStart: string;
  name: string;
}) {
  const story = { version: 1, name, scene: 'gym' };
  await sql`insert into public.week_stories (squad_id, week_start, story)
    values (${squad}, ${weekStart}, ${JSON.stringify(story)}::jsonb)`.execute(db);
}

/** Awards a week's titles to a member, as the Sunday awards save them. */
async function award(
  { squad, weekStart, member }: { squad: string; weekStart: string; member: string },
  titles: readonly { title: string; speech: string; badge?: typeof shield }[],
) {
  await sql`insert into public.weekly_awards (squad_id, week_start, given_at)
    values (${squad}, ${weekStart}, now()) on conflict do nothing`.execute(db);
  const stored = {
    version: 1,
    titles: titles.map(({ title, speech, badge }) => ({
      title,
      speech,
      move: 'pump',
      ...(badge === undefined ? {} : { badge }),
    })),
  };
  await sql`insert into public.weekly_award_winners (squad_id, week_start, member_id, position, award)
    values (${squad}, ${weekStart}, ${member}, (select count(*) from public.weekly_award_winners
      where squad_id = ${squad} and week_start = ${weekStart}), ${JSON.stringify(stored)}::jsonb)`.execute(
    db,
  );
}

describe('/me/titles and /me/equipped-title', () => {
  it('shows the badge board, the latest won first, and wears the latest until one is equipped', async () => {
    const me = await signUp();
    await profileOf(me, { nickname: '小米' });
    const squad = await squadOf(me);
    expect(await call({ method: 'GET', path: '/me/titles', token: me.token })).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: { version: 1, teamBadges: [], titles: [] },
    });
    await award({ squad: squad, weekStart: '2026-10-12', member: me.userId }, [
      { title: '早八战神', speech: '天天七点' },
    ]);
    await award({ squad: squad, weekStart: '2026-10-19', member: me.userId }, [
      { title: '冷面杀手', speech: '一句话不说', badge: hexagon },
    ]);
    await award({ squad: squad, weekStart: '2026-10-26', member: me.userId }, [
      { title: '早八战神', speech: '又是七点', badge: shield },
    ]);
    // Each week carries its squad's name as its 战报 froze it, even after a rename.
    await freeze({ squad, weekStart: '2026-10-26', name: '早八战队' });
    const board = {
      version: 1,
      teamBadges: [],
      titles: [
        {
          title: '早八战神',
          badge: shownShield,
          weeks: [
            { weekStart: '2026-10-26', speech: '又是七点', squadName: '早八战队' },
            { weekStart: '2026-10-12', speech: '天天七点' },
          ],
        },
        {
          title: '冷面杀手',
          badge: shownHexagon,
          weeks: [{ weekStart: '2026-10-19', speech: '一句话不说' }],
        },
      ],
      worn: '早八战神',
    };
    expect((await call({ method: 'GET', path: '/me/titles', token: me.token })).body).toStrictEqual(
      board,
    );

    const equip = (title: string | null) =>
      call({
        method: 'PUT',
        path: '/me/equipped-title',
        token: me.token,
        body: { version: 1, title },
      });
    const worn = { ...board, worn: '冷面杀手', equipped: '冷面杀手' };
    expect((await equip('冷面杀手')).body).toStrictEqual(worn);
    expect((await equip('冷面杀手')).status).toBe(200);
    expect((await call({ method: 'GET', path: '/me/titles', token: me.token })).body).toStrictEqual(
      worn,
    );
    const notWon = await equip('夜跑王');
    expect([notWon.status, reason(notWon)]).toStrictEqual([400, 'TITLE_NOT_WON']);
    expect((await equip(null)).body).toStrictEqual(board);

    // Every change is logged with the whole profile, and a repeat logs nothing.
    const logged = await sql<{ equipped_title: string | null; nickname: string }>`
      select equipped_title, nickname from public.profile_events
      where member_id = ${me.userId} order by id`.execute(db);
    expect(logged.rows).toStrictEqual([
      { equipped_title: null, nickname: '小米' },
      { equipped_title: '冷面杀手', nickname: '小米' },
      { equipped_title: null, nickname: '小米' },
    ]);
    // A profile save keeps the title worn.
    await equip('冷面杀手');
    await profileOf(me, { nickname: '小米米' });
    expect(
      z
        .object({ worn: z.string() })
        .parse((await call({ method: 'GET', path: '/me/titles', token: me.token })).body).worn,
    ).toBe('冷面杀手');
    expect((await call({ method: 'GET', path: '/me/titles' })).status).toBe(401);
  });

  it('refuses to wear a title before the member has a profile', async () => {
    const me = await signUp();
    const squad = await squadOf(me);
    await award({ squad: squad, weekStart: '2026-10-12', member: me.userId }, [
      { title: '早八战神', speech: '天天七点' },
    ]);
    const response = await call({
      method: 'PUT',
      path: '/me/equipped-title',
      token: me.token,
      body: { version: 1, title: '早八战神' },
    });
    expect([response.status, reason(response)]).toStrictEqual([400, 'PROFILE_MISSING']);
  });
});

const WeekStartText = z.iso.date();

describe('GET /squads/{squadId}/members/{memberId}/card', () => {
  it('shows a squadmate’s card, with award lines only from this squad', async () => {
    const [me, mate, stranger] = [await signUp(), await signUp(), await signUp()];
    await profileOf(me, { nickname: '小米' });
    await profileOf(mate, { nickname: '阿杰', jerseyNumber: 7 });
    const squad = await squadOf(me, mate);
    const elsewhere = await squadOf(await signUp());
    await alsoJoinedEarlier(db, { squad: elsewhere, member: mate.userId });
    await award({ squad: squad, weekStart: '2026-10-19', member: mate.userId }, [
      { title: '冷面杀手', speech: '一句话不说', badge: hexagon },
    ]);
    await award({ squad: elsewhere, weekStart: '2026-10-26', member: mate.userId }, [
      { title: '冷面杀手', speech: '别的小队的事', badge: hexagon },
    ]);
    await freeze({ squad, weekStart: '2026-10-19', name: '这个小队' });
    await freeze({ squad: elsewhere, weekStart: '2026-10-26', name: '别的小队' });
    await call({
      method: 'PUT',
      path: '/me/equipped-title',
      token: mate.token,
      body: { version: 1, title: '冷面杀手' },
    });

    // Today is a rest day on their plan, so a 练了 makes it a training day of its sport.
    const now = new Date();
    const monday = new Date(now.getTime() - ((now.getUTCDay() + 6) % 7) * 86_400_000)
      .toISOString()
      .slice(0, 10);
    const planPath = `/me/weekly-plans/${monday}`;
    const current = z
      .object({ days: z.array(z.record(z.string(), z.unknown())) })
      .parse((await call({ method: 'GET', path: planPath, token: mate.token })).body).days;
    const restToday = current.map((day, at) =>
      at === (now.getUTCDay() + 6) % 7 ? { kind: 'rest' } : day,
    );
    const rested = await call({
      method: 'PUT',
      path: planPath,
      token: mate.token,
      body: { version: 1, days: restToday },
    });
    expect(rested.status).toBe(200);

    // A 练了 sent only to the other squad still counts in their own week.
    const runId = randomUUID();
    const createdAt = new Date();
    const trained = await call({
      method: 'PUT',
      path: `/check-ins/${runId}`,
      token: mate.token,
      body: {
        version: 1,
        // Their zone is UTC.
        day: createdAt.toISOString().slice(0, 10),
        createdAt: createdAt.toISOString(),
        audience: [elsewhere],
        kind: 'trained',
        training: { sport: 'run' },
      },
    });
    expect(trained.status).toBe(201);
    const today = createdAt;
    const weekday = (today.getUTCDay() + 6) % 7;
    const weekStart = new Date(today.getTime() - weekday * 86_400_000).toISOString().slice(0, 10);
    const fuel = await call({
      method: 'PUT',
      path: `/me/weekly-plans/${weekStart}/fuel-goals`,
      token: mate.token,
      body: { version: 1, goals: [{ kind: 'suggested', suggestion: 'water' }] },
    });
    expect(fuel.status).toBe(200);

    const path = `/squads/${squad}/members/${mate.userId}/card`;
    const card = await call({ method: 'GET', path, token: me.token });
    expect(card.status).toBe(200);
    expect(card.body).toMatchObject({
      version: 1,
      member: mate.userId,
      character: { nickname: '阿杰', look },
      jerseyNumber: 7,
      squadPlace: 2,
      trainedDays: 1,
      healthyMeals: 0,
      cheatMeals: 0,
      disclaimers: 0,
      titles: [
        {
          title: '冷面杀手',
          badge: shownHexagon,
          weeks: [
            { weekStart: '2026-10-26' },
            { weekStart: '2026-10-19', speech: '一句话不说', squadName: '这个小队' },
          ],
        },
      ],
      worn: '冷面杀手',
    });
    expect(JSON.stringify(card.body)).not.toContain('别的小队');
    // Their week on the card is the one their own home counts.
    const theirToday = await call({
      method: 'GET',
      path: `/squads/${elsewhere}/today`,
      token: mate.token,
    });
    const own = z
      .object({ me: z.object({ week: z.object({ trainedDays: z.int(), plannedDays: z.int() }) }) })
      .parse(theirToday.body).me.week;
    expect(own.trainedDays).toBe(1);
    const week = z
      .object({
        week: z.object({
          trainedDays: z.int(),
          plannedDays: z.int(),
          weekStart: z.string(),
          days: z.array(z.unknown()),
          marks: z.array(z.unknown()),
          fuelGoals: z.array(z.unknown()),
        }),
      })
      .parse(card.body).week;
    expect({ trainedDays: week.trainedDays, plannedDays: week.plannedDays }).toStrictEqual(own);
    // The back is their 出赛表 for this week only: the plan, the day's 练了 with its sport, and
    // the week's 饮食小目标.
    expect(week.weekStart).toBe(weekStart);
    // They joined just now: their W1 is this week (or, just after midnight on a Monday, the one before).
    const { firstWeek } = z
      .object({ week: z.object({ firstWeek: WeekStartText }) })
      .parse(card.body).week;
    expect(firstWeek <= weekStart).toBe(true);
    expect(Date.parse(weekStart) - Date.parse(firstWeek)).toBeLessThanOrEqual(7 * 86_400_000);
    // Their today, on their calendar, is the row their 出赛表 shades.
    const { today: cardToday } = z
      .object({ week: z.object({ today: z.iso.date() }) })
      .parse(card.body).week;
    expect(cardToday).toBe(today.toISOString().slice(0, 10));
    expect(week.days).toHaveLength(7);
    expect(week.marks).toHaveLength(7);
    // The run went only to the other squad, so this squad's card never says what it was.
    expect(week.marks).toStrictEqual(Array.from({ length: 7 }, () => ({ status: 'none' })));
    // Nor does the plan: the rest day it turned into a run still reads as a rest day here.
    expect(week.days[weekday]).toStrictEqual({ kind: 'rest' });
    expect(week.fuelGoals).toStrictEqual([{ kind: 'suggested', suggestion: 'water' }]);
    // A 练了 sent to this squad shows with its sport.
    const later = new Date();
    const swimId = randomUUID();
    const shared = await call({
      method: 'PUT',
      path: `/check-ins/${swimId}`,
      token: mate.token,
      body: {
        version: 1,
        day: today.toISOString().slice(0, 10),
        createdAt: later.toISOString(),
        audience: [squad],
        kind: 'trained',
        training: { sport: 'swim' },
      },
    });
    expect(shared.status).toBe(201);
    const again = await call({ method: 'GET', path, token: me.token });
    const { marks, days } = z
      .object({ week: z.object({ marks: z.array(z.unknown()), days: z.array(z.unknown()) }) })
      .parse(again.body).week;
    expect(marks[weekday]).toStrictEqual({
      status: 'trained',
      sport: 'swim',
      sports: [{ sport: 'swim' }],
    });
    expect(days[weekday]).toStrictEqual({ kind: 'train', sport: 'swim' });
    expect(marks.filter((mark) => JSON.stringify(mark) === '{"status":"none"}')).toHaveLength(6);
    // With the swim deleted, and then the run that made the day a training day, it reads as
    // the rest day it was planned as.
    for (const id of [swimId, runId]) {
      const deleted = await call({ method: 'DELETE', path: `/check-ins/${id}`, token: mate.token });
      expect(deleted.status).toBe(204);
      const after = z
        .object({ week: z.object({ days: z.array(z.unknown()) }) })
        .parse((await call({ method: 'GET', path, token: me.token })).body).week.days;
      expect(after[weekday]).toStrictEqual({ kind: 'rest' });
    }
    expect(z.object({ joinedAt: z.iso.datetime() }).safeParse(card.body).success).toBe(true);

    // The squad's today shows the title beside the name.
    const squadToday = await call({
      method: 'GET',
      path: `/squads/${squad}/today`,
      token: me.token,
    });
    const members = z
      .object({ members: z.array(z.object({ member: z.string(), title: z.unknown().optional() })) })
      .parse(squadToday.body).members;
    expect(members.find(({ member }) => member === mate.userId)?.title).toStrictEqual({
      title: '冷面杀手',
      badge: shownHexagon,
    });
    expect(members.find(({ member }) => member === me.userId)?.title).toBeUndefined();

    const outsider = await call({ method: 'GET', path, token: stranger.token });
    expect(outsider.status).toBe(403);
    const notHere = await call({
      method: 'GET',
      path: `/squads/${squad}/members/${stranger.userId}/card`,
      token: me.token,
    });
    expect([notHere.status, reason(notHere)]).toStrictEqual([404, 'SQUAD_MEMBER_UNKNOWN']);
  });
});

describe('the team’s badges', () => {
  it('shows the badges the team gave apart from the titles, ×N, on the board and the card', async () => {
    const me = await signUp();
    const mate = await signUp();
    await profileOf(me, { nickname: '小米' });
    await profileOf(mate, { nickname: '阿杰' });
    const squad = await squadOf(me, mate);
    const badge = `bug-${randomUUID().slice(0, 8)}`;
    await rewards.putBadge({
      id: badge,
      names: { 'zh-Hans': '捉虫队', 'zh-Hant': '捉蟲隊', en: 'Bug Hunter' },
      glyph: 'ladybug.fill',
      tone: '#E65345',
      offered: true,
    });
    await rewards.putTrigger({ kind: 'badge', id: badge, way: 'team', offered: true });
    const admin = RewardMember.parse(randomUUID());
    for (let times = 0; times < 2; times += 1) {
      expect(
        await rewards.give({
          member: RewardMember.parse(mate.userId),
          reward: { kind: 'badge', id: badge },
          admin,
        }),
      ).toBe(true);
    }
    const shown = {
      id: badge,
      name: { zhHans: '捉虫队', en: 'Bug Hunter', zhHant: '捉蟲隊' },
      glyph: 'ladybug.fill',
      tone: '#E65345',
      times: 2,
    };
    const mine = await call({ method: 'GET', path: '/me/titles', token: mate.token });
    expect(mine.body).toMatchObject({ version: 1, teamBadges: [shown], titles: [] });
    expect(
      z
        .object({ teamBadges: z.tuple([z.object({ latestAt: z.iso.datetime() })]) })
        .safeParse(mine.body).success,
    ).toBe(true);
    const card = await call({
      method: 'GET',
      path: `/squads/${squad}/members/${mate.userId}/card`,
      token: me.token,
    });
    expect(card.body).toMatchObject({ teamBadges: [shown], titles: [] });
    expect((await call({ method: 'GET', path: '/me/titles', token: me.token })).body).toMatchObject(
      { teamBadges: [] },
    );
  });
});
