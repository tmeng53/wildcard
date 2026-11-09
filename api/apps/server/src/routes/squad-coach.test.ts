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
  createCoachHiring,
  createCoachLetters,
  createPostgresCoachLetters,
  createPostgresCoachSettings,
  createPostgresCoachStores,
  createPostgresCoachActivity,
  createPostgresCoachCatalog,
  createPostgresCoachHiring,
} from '@wildcard/coach';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { createCoachGifts, createPostgresGiftStore } from '@wildcard/unlocks';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createMemoryRateLimit } from '../adapters/memory-rate-limit.js';
import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { coachNamesIn } from '../flows/coach-names.js';
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
  weatherOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import {
  unusedWeeklyAwards,
  unusedWeekSummaryWords,
  unusedUnlocks,
  ignoredNotices,
  unusedFeedback,
  noRewards,
} from '../test-kit/weekly-awards.js';
import { catalogOn } from '../test-kit/public-routes.js';

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
  push: pushOn(db),
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  aiConsent: aiConsentOn(db),
  nudges: nudgesOn(db),
  weather: weatherOn(db),
  scenes: scenesOn(db),
  switches: switchesOn(db),
  weeklyAwards: unusedWeeklyAwards,
  unlocks: unusedUnlocks,
  gifts: createCoachGifts({ store: createPostgresGiftStore(db) }),
  rewards: noRewards,
  weekSummaryWords: unusedWeekSummaryWords,
  coachHiring: createCoachHiring({
    hiring: createPostgresCoachHiring(db),
    catalog: createPostgresCoachCatalog(db),
  }),
  coachActivity: createCoachActivity({ store: createPostgresCoachActivity(db) }),
  // No model here: the coach module's own tests write letters.
  coachLetters: createCoachLetters({
    settings: createPostgresCoachSettings(db),
    catalog: createPostgresCoachCatalog(db),
    letters: createPostgresCoachLetters(db),
    memory: createPostgresCoachStores(db).memory,
    usage: createPostgresCoachStores(db).usage,
    squadWeek: () => Promise.reject(new Error('unused')),
    aiConsented: () => Promise.reject(new Error('unused')),
    clock: () => new Date(),
  }),
  ...ignoredNotices,
  ...unusedFeedback,
  coachNames: coachNamesIn({
    coaches: createPostgresCoachCatalog(db),
    members,
    squads: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent: () => Promise.resolve(true),
    }),
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

const card = {
  id: 'xiaohun',
  tier: 'entry',
  name: '小混',
  title: '混混教练',
  catchphrase: '先动起来，证书以后再说',
  background: '体育学院刚毕业，该学的都学了，就是证还没考下来',
  yearsCoaching: 0,
  experience: '热情满格',
  style: '松弛、自嘲、陪着练',
  tags: ['体院应届', '懂行', '松弛', '风趣'],
  pay: '管饭就行',
  look: 'xiaohun',
};

describe('GET /coaches', () => {
  it('lists the coaches a squad can hire with their 简历, never their soul', async () => {
    const me = await signUp();
    const { status, body } = await call({ method: 'GET', path: '/coaches', token: me.token });
    expect([status, body]).toStrictEqual([200, { version: 1, coaches: [card] }]);
    expect(JSON.stringify(body)).not.toContain('你是小混');
    expect((await call({ method: 'GET', path: '/coaches' })).status).toBe(401);
  });
});

describe('/squads/{squadId}/coach', () => {
  it('lets the captain hire, keep and fire the coach, and every member see it', async () => {
    const [captain, mate] = [await signUp(), await signUp()];
    const squad = await squadOf(captain, mate);
    const path = `/squads/${squad}/coach`;

    const none = { version: 1, coach: null, since: null };
    expect(await call({ method: 'GET', path, token: mate.token })).toMatchObject({
      status: 200,
      body: { ...none, canHire: false },
    });

    const hire = { version: 1, coach: 'xiaohun' };
    const before = Date.now();
    const hired = await call({ method: 'PUT', path, token: captain.token, body: hire });
    expect(hired).toMatchObject({ status: 201, body: { version: 1, coach: card, canHire: true } });
    const since = Date.parse(z.object({ since: z.string() }).parse(hired.body).since);
    expect(since).toBeGreaterThanOrEqual(before - 1000);

    // A retry, and what a teammate sees.
    const again = await call({ method: 'PUT', path, token: captain.token, body: hire });
    expect([again.status, again.body]).toStrictEqual([200, hired.body]);
    expect(await call({ method: 'GET', path, token: mate.token })).toMatchObject({
      status: 200,
      body: { coach: card, canHire: false },
    });

    // Only the captain hires and fires.
    const byMate = await call({ method: 'PUT', path, token: mate.token, body: hire });
    expect([byMate.status, reason(byMate)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);
    const firedByMate = await call({ method: 'DELETE', path, token: mate.token });
    expect([firedByMate.status, reason(firedByMate)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);

    const fired = await call({ method: 'DELETE', path, token: captain.token });
    expect([fired.status, fired.body]).toStrictEqual([200, { ...none, canHire: true }]);
    const firedAgain = await call({ method: 'DELETE', path, token: captain.token });
    expect([firedAgain.status, firedAgain.body]).toStrictEqual([200, fired.body]);
  });

  it('refuses a coach that isn’t offered and anyone outside the squad', async () => {
    const [captain, stranger] = [await signUp(), await signUp()];
    const path = `/squads/${await squadOf(captain)}/coach`;
    const nobody = await call({
      method: 'PUT',
      path,
      token: captain.token,
      body: { version: 1, coach: 'nobody' },
    });
    expect([nobody.status, reason(nobody)]).toStrictEqual([400, 'COACH_NOT_OFFERED']);
    for (const method of ['GET', 'PUT', 'DELETE']) {
      const response = await call({
        method,
        path,
        token: stranger.token,
        ...(method === 'PUT' ? { body: { version: 1, coach: 'xiaohun' } } : {}),
      });
      expect([method, response.status, reason(response)]).toStrictEqual([
        method,
        403,
        'SQUAD_NOT_JOINED',
      ]);
    }
  });
});

/** A 练了 the member posts to this squad a minute ago; its id. */
async function checkIn(token: string, squad: string) {
  const at = new Date(Date.now() - 60_000);
  const id = randomUUID();
  const posted = await call({
    method: 'PUT',
    path: `/check-ins/${id}`,
    token,
    body: {
      version: 1,
      day: at.toISOString().slice(0, 10),
      createdAt: at.toISOString(),
      audience: [squad],
      kind: 'trained',
      training: { sport: 'run' },
    },
  });
  expect(posted.status).toBe(201);
  return id;
}

/** What the coach's wake for this check-in saves: its reply, or its line for a day. */
async function coachSaid(
  squad: string,
  said:
    { checkIn: string; text: string | null; emoji: string | null } | { day: string; text: string },
) {
  if ('day' in said) {
    await sql`insert into public.coach_notes (squad_id, coach_id, day, text)
      values (${squad}, 'xiaohun', ${said.day}, ${said.text})`.execute(db);
    return;
  }
  await sql`insert into public.coach_replies (squad_id, check_in_id, coach_id, text, emoji)
    values (${squad}, ${said.checkIn}, 'xiaohun', ${said.text}, ${said.emoji})`.execute(db);
}

describe('GET /squads/{squadId}/coach/activity', () => {
  const speaker = { id: 'xiaohun', name: '小混', look: 'xiaohun' };

  it('gives members the newest 战术板 line and the replies to the posts they ask about', async () => {
    const [captain, mate] = [await signUp(), await signUp()];
    const squad = await squadOf(captain, mate);
    const path = `/squads/${squad}/coach/activity`;
    expect(await call({ method: 'GET', path, token: mate.token })).toMatchObject({
      status: 200,
      body: { version: 1, note: null, replies: [], answers: [] },
    });

    const [run, swim, quiet] = [
      await checkIn(captain.token, squad),
      await checkIn(mate.token, squad),
      await checkIn(mate.token, squad),
    ];
    await coachSaid(squad, { day: '2026-11-02', text: '先动起来' });
    await coachSaid(squad, { day: '2026-11-03', text: '今天谁先动，谁就是队长' });
    await coachSaid(squad, { checkIn: run, text: '腿还在吗', emoji: '💪' });
    await coachSaid(squad, { checkIn: swim, text: null, emoji: '🔥' });
    // The mate replied to the coach under the run, and it answered.
    const asked = randomUUID();
    await sql`insert into public.check_in_comments (id, check_in_id, member_id, text, reply_to_coach, commented_at)
      values (${asked}, ${run}, ${mate.userId}, '在呢', 'xiaohun', now())`.execute(db);
    // Its answer @s the captain, so the app shows the tag that opens their card.
    await sql`with answer as (
        insert into public.coach_answers (squad_id, check_in_id, comment_id, coach_id, text)
        values (${squad}, ${run}, ${asked}, 'xiaohun', '@队长 那就再跑一圈') returning id
      )
      insert into public.coach_answer_mentions (answer_id, member_id, position)
      select id, ${captain.userId}, 0 from answer`.execute(db);

    const read = await call({
      method: 'GET',
      path: `${path}?checkIns=${run},${swim},${quiet}`,
      token: mate.token,
    });
    expect(read.status).toBe(200);
    const body = z
      .object({
        note: z.object({ at: z.iso.datetime() }).loose(),
        replies: z.array(z.object({ checkInId: z.string(), at: z.iso.datetime() }).loose()),
        answers: z.array(z.object({ at: z.iso.datetime() }).loose()),
      })
      .loose()
      .parse(read.body);
    expect({
      ...body,
      note: { ...body.note, at: 'at' },
      replies: body.replies
        .map((reply) => ({ ...reply, at: 'at' }))
        .toSorted((a, b) => (a.checkInId === run ? -1 : b.checkInId === run ? 1 : 0)),
      answers: body.answers.map((answer) => ({ ...answer, at: 'at' })),
    }).toStrictEqual({
      version: 1,
      note: {
        day: '2026-11-03',
        text: '今天谁先动，谁就是队长',
        coach: speaker,
        at: 'at',
        timeZone: 'America/New_York',
      },
      replies: [
        { checkInId: run, coach: speaker, text: '腿还在吗', emoji: '💪', at: 'at' },
        { checkInId: swim, coach: speaker, text: null, emoji: '🔥', at: 'at' },
      ],
      answers: [
        {
          checkInId: run,
          commentId: asked,
          coach: speaker,
          text: '@队长 那就再跑一圈',
          mentions: [captain.userId],
          at: 'at',
        },
      ],
    });

    // The coach's word stays after the squad fires it.
    await call({
      method: 'PUT',
      path: `/squads/${squad}/coach`,
      token: captain.token,
      body: { version: 1, coach: 'xiaohun' },
    });
    await call({ method: 'DELETE', path: `/squads/${squad}/coach`, token: captain.token });
    const afterFiring = await call({
      method: 'GET',
      path: `${path}?checkIns=${run}`,
      token: captain.token,
    });
    expect(afterFiring.body).toMatchObject({ replies: [{ checkInId: run, text: '腿还在吗' }] });

    // A deleted post takes its reply.
    await sql`delete from public.check_ins where id = ${run}`.execute(db);
    const afterDelete = await call({
      method: 'GET',
      path: `${path}?checkIns=${run}`,
      token: captain.token,
    });
    expect(afterDelete.body).toMatchObject({ replies: [], answers: [] });
  });

  it('gives the caller its morning note only while its coach switch is on', async () => {
    const captain = await signUp();
    const squad = await squadOf(captain);
    const hired = await call({
      method: 'PUT',
      path: `/squads/${squad}/coach`,
      token: captain.token,
      body: { version: 1, coach: 'xiaohun' },
    });
    expect(hired.status).toBe(201);
    const written = await sql<{ id: string }>`
      insert into public.coach_member_notes (squad_id, member_id, coach_id, day, text)
      values (${squad}, ${captain.userId}, 'xiaohun', current_date, '今天慢慢跑')
      returning id`.execute(db);
    const id = written.rows[0]?.id;
    await sql`insert into public.coach_member_note_deliveries (note_id) values (${id})`.execute(db);
    const path = `/squads/${squad}/coach/activity`;
    expect((await call({ method: 'GET', path, token: captain.token })).body).toMatchObject({
      memberNote: { text: '今天慢慢跑' },
    });

    const off = await call({
      method: 'PUT',
      path: '/me/push-settings',
      token: captain.token,
      body: { version: 1, settings: { dailyProgress: true, coach: false } },
    });
    expect(off.status).toBe(200);
    const quiet = await call({ method: 'GET', path, token: captain.token });
    expect(quiet.status).toBe(200);
    expect(quiet.body).not.toHaveProperty('memberNote');
    // Fired again, so no other test's coach run finds this squad hired.
    await call({ method: 'DELETE', path: `/squads/${squad}/coach`, token: captain.token });
  });

  it('shows the note’s challenge and keeps the caller’s first answer to it', async () => {
    const [captain, mate] = [await signUp(), await signUp()];
    const squad = await squadOf(captain);
    await call({
      method: 'PUT',
      path: `/squads/${squad}/coach`,
      token: captain.token,
      body: { version: 1, coach: 'xiaohun' },
    });
    const written = await sql<{ id: string }>`
      insert into public.coach_member_notes
        (squad_id, member_id, coach_id, day, text, challenge_title, challenge_amount, challenge_unit)
      values (${squad}, ${captain.userId}, 'xiaohun', current_date, '今天多喝水', '喝水', 8, '杯')
      returning id`.execute(db);
    const id = Number(written.rows[0]?.id);
    await sql`insert into public.coach_member_note_deliveries (note_id) values (${id})`.execute(db);
    const path = `/squads/${squad}/coach/activity`;
    expect((await call({ method: 'GET', path, token: captain.token })).body).toMatchObject({
      memberNote: { id, text: '今天多喝水', challenge: { title: '喝水', amount: 8, unit: '杯' } },
    });
    const answer = (token: string, said: string) =>
      call({
        method: 'PUT',
        path: `/squads/${squad}/coach/notes/${String(id)}/challenge`,
        token,
        body: { version: 1, answer: said },
      });
    expect(await answer(captain.token, 'accepted')).toMatchObject({
      status: 200,
      body: { version: 1, noteId: id, answer: 'accepted' },
    });
    expect((await answer(captain.token, 'declined')).body).toMatchObject({ answer: 'accepted' });
    expect((await answer(captain.token, 'maybe')).status).toBe(400);
    // Only the member it was written to, in their squad.
    expect((await answer(mate.token, 'accepted')).status).toBe(403);
    expect((await call({ method: 'GET', path, token: captain.token })).body).toMatchObject({
      memberNote: { challenge: { title: '喝水', answer: 'accepted' } },
    });
    await call({ method: 'DELETE', path: `/squads/${squad}/coach`, token: captain.token });
  });

  it('gives the caller today’s challenge and lets them mark it done once, on its day', async () => {
    const [captain, mate, third] = [await signUp(), await signUp(), await signUp()];
    const squad = await squadOf(captain, mate, third);
    await call({
      method: 'PUT',
      path: `/squads/${squad}/coach`,
      token: captain.token,
      body: { version: 1, coach: 'xiaohun' },
    });
    // Today and yesterday on the squad's clock.
    const squadDay = (daysAgo: number) =>
      sql<{ day: string }>`
      select to_char((now() at time zone coalesce((select time_zone from public.squad_time_zones
        where squad_id = ${squad} order by week_start desc, id desc limit 1), 'America/New_York'))::date
        - ${daysAgo}::int, 'YYYY-MM-DD') as day`.execute(db);
    const today = (await squadDay(0)).rows[0]?.day ?? '';
    const yesterday = (await squadDay(1)).rows[0]?.day ?? '';
    const note = async (
      member: string,
      {
        day,
        challenge,
      }: { day: string; challenge?: { title: string; amount?: number; unit?: string } },
    ) => {
      const written = await sql<{ id: string }>`
        insert into public.coach_member_notes
          (squad_id, member_id, coach_id, day, text, challenge_title, challenge_amount, challenge_unit)
        values (${squad}, ${member}, 'xiaohun', ${day}::date, '今天多喝水',
          ${challenge?.title ?? null}, ${challenge?.amount ?? null}::int, ${challenge?.unit ?? null})
        returning id`.execute(db);
      const id = Number(written.rows[0]?.id);
      await sql`insert into public.coach_member_note_deliveries (note_id) values (${id})`.execute(
        db,
      );
      return id;
    };
    const path = `/squads/${squad}/coach/challenge`;
    const todays = async (token: string) => (await call({ method: 'GET', path, token })).body;
    const complete = (token: string, id: number) =>
      call({
        method: 'PUT',
        path: `/squads/${squad}/coach/notes/${String(id)}/challenge/completion`,
        token,
        body: { version: 1 },
      });
    expect(await todays(mate.token)).toStrictEqual({ version: 1, today: null });

    const old = await note(mate.userId, { day: yesterday, challenge: { title: '拉伸' } });
    const water = await note(mate.userId, {
      day: today,
      challenge: { title: '喝水', amount: 8, unit: '杯' },
    });
    expect(await todays(mate.token)).toStrictEqual({
      version: 1,
      today: { noteId: water, day: today, challenge: { title: '喝水', amount: 8, unit: '杯' } },
    });
    // Only on its own day.
    const late = await complete(mate.token, old);
    expect([late.status, reason(late)]).toStrictEqual([400, 'COACH_CHALLENGE_DAY_OVER']);

    const done = await complete(mate.token, water);
    expect(done).toMatchObject({
      status: 200,
      body: { version: 1, noteId: water, completedBy: 'member' },
    });
    const DoneBody = z.object({ completedAt: z.iso.datetime() }).loose();
    const at = DoneBody.parse(done.body).completedAt;
    // The first one stands.
    expect((await complete(mate.token, water)).body).toMatchObject({ completedAt: at });
    expect(await todays(mate.token)).toMatchObject({
      today: { noteId: water, challenge: { completedAt: at, completedBy: 'member' } },
    });
    // Only the member it was written to; a note without a challenge has nothing to do.
    expect((await complete(captain.token, water)).status).toBe(404);
    const plain = await note(captain.userId, { day: today });
    const none = await complete(captain.token, plain);
    expect([none.status, reason(none)]).toStrictEqual([400, 'COACH_NOTE_NO_CHALLENGE']);
    expect(await todays(captain.token)).toStrictEqual({ version: 1, today: null });

    // One let go (算了) can't be marked done.
    const stretch = await note(third.userId, { day: today, challenge: { title: '拉伸' } });
    const decline = (body: object) =>
      call({
        method: 'PUT',
        path: `/squads/${squad}/coach/notes/${String(stretch)}/challenge`,
        token: third.token,
        body: { version: 1, ...body },
      });
    // Why they let it go comes only with 算了, one line of at most 60 characters.
    expect((await decline({ answer: 'accepted', reason: '腿疼' })).status).toBe(400);
    expect((await decline({ answer: 'declined', reason: '疼'.repeat(61) })).status).toBe(400);
    expect((await decline({ answer: 'declined', reason: '   ' })).status).toBe(400);
    expect(await decline({ answer: 'declined', reason: ' 我腿疼 ' })).toMatchObject({
      status: 200,
      body: { version: 1, noteId: stretch, answer: 'declined', reason: '我腿疼' },
    });
    const declined = await complete(third.token, stretch);
    expect([declined.status, reason(declined)]).toStrictEqual([400, 'COACH_CHALLENGE_DECLINED']);
    expect(await todays(third.token)).toMatchObject({
      today: { noteId: stretch, challenge: { answer: 'declined', reason: '我腿疼' } },
    });

    // With the coach switch off, it doesn't show.
    await call({
      method: 'PUT',
      path: '/me/push-settings',
      token: mate.token,
      body: { version: 1, settings: { dailyProgress: true, coach: false } },
    });
    expect(await todays(mate.token)).toStrictEqual({ version: 1, today: null });
    await call({ method: 'DELETE', path: `/squads/${squad}/coach`, token: captain.token });
  });

  it('refuses anyone outside the squad, and check-in ids that aren’t', async () => {
    const [captain, stranger] = [await signUp(), await signUp()];
    const squad = await squadOf(captain);
    const path = `/squads/${squad}/coach/activity`;
    const outside = await call({ method: 'GET', path, token: stranger.token });
    expect([outside.status, reason(outside)]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
    expect((await call({ method: 'GET', path })).status).toBe(401);
    const bad = await call({ method: 'GET', path: `${path}?checkIns=nope`, token: captain.token });
    expect(bad.status).toBe(400);
    const many = Array.from({ length: 101 }, () => randomUUID()).join(',');
    const tooMany = await call({
      method: 'GET',
      path: `${path}?checkIns=${many}`,
      token: captain.token,
    });
    expect(tooMany.status).toBe(400);
  });
});

describe('/squads/{squadId}/coach/cards', () => {
  const speaker = { id: 'xiaohun', name: '小混', look: 'xiaohun' };
  const CardsBody = z.object({
    stack: z.array(z.object({ kind: z.string(), id: z.string() }).loose()),
    earlier: z.array(z.object({ kind: z.string(), id: z.string() }).loose()),
  });
  const ids = (cards: readonly { kind: string; id: string }[]) =>
    cards.map(({ kind, id }) => `${kind}:${id}`);
  // The stack is the squad's coach now; a coach that left is 以前 whole.
  const hire = async (captain: { token: string }, squad: string) => {
    const hired = await call({
      method: 'PUT',
      path: `/squads/${squad}/coach`,
      token: captain.token,
      body: { version: 1, coach: 'xiaohun' },
    });
    expect(hired.status).toBe(201);
  };
  const fire = (captain: { token: string }, squad: string) =>
    call({ method: 'DELETE', path: `/squads/${squad}/coach`, token: captain.token });

  it('stacks what the coach has for the caller, oldest first, and moves a seen card to 以前', async () => {
    const [captain, mate] = [await signUp(), await signUp()];
    const squad = await squadOf(captain, mate);
    await hire(captain, squad);
    const path = `/squads/${squad}/coach/cards`;
    expect(await call({ method: 'GET', path, token: mate.token })).toMatchObject({
      status: 200,
      body: { version: 1, stack: [], earlier: [] },
    });

    const today = new Date().toISOString().slice(0, 10);
    await coachSaid(squad, { day: today, text: '今天谁先动，谁就是队长' });
    const written = await sql<{ id: string }>`
      insert into public.coach_member_notes
        (squad_id, member_id, coach_id, day, text, challenge_title, challenge_amount,
         challenge_unit, challenge_line)
      values (${squad}, ${mate.userId}, 'xiaohun', current_date, '今天随便动动', '拉伸', 5, '分钟',
        '昨天跑完腿还紧，睡前拉一拉。')
      returning id`.execute(db);
    const note = String(written.rows[0]?.id);
    // Not delivered yet: nothing of it shows.
    expect(
      ids(CardsBody.parse((await call({ method: 'GET', path, token: mate.token })).body).stack),
    ).toStrictEqual([`board:${today}`]);
    await sql`insert into public.coach_member_note_deliveries (note_id) values (${note})`.execute(
      db,
    );
    await sql`insert into public.rewards (kind, id) values ('piece', 'cards-towel') on conflict do nothing`.execute(
      db,
    );
    await sql`insert into public.reward_triggers (reward_kind, reward_id, kind)
      values ('piece', 'cards-towel', 'coach') on conflict do nothing`.execute(db);
    await sql`insert into public.grants (member_id, reward_kind, reward_id, via, coach_id, squad_id, line, given_by, at)
      values (${mate.userId}, 'piece', 'cards-towel', 'coach', 'xiaohun', ${squad}, '练完擦汗', 'coach', now())`.execute(
      db,
    );
    const mine = await checkIn(mate.token, squad);
    const theirs = await checkIn(captain.token, squad);
    await coachSaid(squad, { checkIn: mine, text: '配速比上周快了', emoji: null });
    await coachSaid(squad, { checkIn: theirs, text: '腿还在吗', emoji: null });

    const read = await call({ method: 'GET', path, token: mate.token });
    expect(read.status).toBe(200);
    const cards = CardsBody.parse(read.body);
    // The coach's lines to check-ins stay under the posts in 动态 (Tracy, 2026-11-09).
    expect(ids(cards.stack)).toStrictEqual([
      `board:${today}`,
      `note:${note}`,
      `challenge:${note}`,
      'gift:cards-towel',
    ]);
    expect(cards.stack[2]).toMatchObject({
      coach: speaker,
      day: today,
      challenge: { title: '拉伸', amount: 5, unit: '分钟', line: '昨天跑完腿还紧，睡前拉一拉。' },
    });
    expect(cards.stack[3]).toMatchObject({
      gift: { pieceId: 'cards-towel', line: '练完擦汗' },
      coach: speaker,
    });

    const seen = (kind: string, id: string) =>
      call({ method: 'PUT', path: `${path}/${kind}/${id}/seen`, token: mate.token });

    expect(await seen('note', note)).toMatchObject({
      status: 200,
      body: { version: 1, kind: 'note', id: note },
    });
    expect((await seen('note', note)).status).toBe(200);
    expect((await seen('gift', 'cards-towel')).status).toBe(200);
    const after = CardsBody.parse((await call({ method: 'GET', path, token: mate.token })).body);
    expect(ids(after.stack)).toStrictEqual([`board:${today}`, `challenge:${note}`]);
    // 以前 is newest first.
    expect(ids(after.earlier)).toStrictEqual(['gift:cards-towel', `note:${note}`]);
    // Seeing the note also put it away on 今天.
    expect(
      (await call({ method: 'GET', path: `/squads/${squad}/coach/activity`, token: mate.token }))
        .body,
    ).not.toHaveProperty('memberNote');
    // Marking someone else's card marks it for the marker only.
    expect(
      (await call({ method: 'PUT', path: `${path}/challenge/${note}/seen`, token: captain.token }))
        .status,
    ).toBe(200);
    expect(
      ids(CardsBody.parse((await call({ method: 'GET', path, token: mate.token })).body).stack),
    ).toContain(`challenge:${note}`);
    // An id not shaped like one of its kind is refused, so nothing odd is kept.
    const odds: readonly (readonly [string, string])[] = [
      ['note', '1e3'],
      ['note', '0x10'],
      ['board', 'today'],
      ['gift', 'A'],
    ];
    for (const [kind, id] of odds) {
      const odd = await call({
        method: 'PUT',
        path: `${path}/${kind}/${id}/seen`,
        token: mate.token,
      });
      expect([odd.status, reason(odd)]).toStrictEqual([400, 'COACH_CARD_ID_INVALID']);
    }
    // With the coach switch off, no morning note or challenge shows; the rest still does.
    const off = await call({
      method: 'PUT',
      path: '/me/push-settings',
      token: mate.token,
      body: { version: 1, settings: { dailyProgress: true, coach: false } },
    });
    expect(off.status).toBe(200);
    const quiet = CardsBody.parse((await call({ method: 'GET', path, token: mate.token })).body);
    expect([...ids(quiet.stack), ...ids(quiet.earlier)].toSorted()).toStrictEqual(
      [`board:${today}`, 'gift:cards-towel'].toSorted(),
    );
    // The captain's stack is the board line alone, with no reply to their post.
    expect(
      ids(CardsBody.parse((await call({ method: 'GET', path, token: captain.token })).body).stack),
    ).toStrictEqual([`board:${today}`]);
    // Fired, its cards go to 以前, unseen ones and the boxed gift too.
    await fire(captain, squad);
    const gone = CardsBody.parse((await call({ method: 'GET', path, token: mate.token })).body);
    expect(gone.stack).toStrictEqual([]);
    expect(ids(gone.earlier).toSorted()).toStrictEqual(
      [`board:${today}`, 'gift:cards-towel'].toSorted(),
    );
  });

  it('shows the coach marking a challenge done as its own card', async () => {
    const mate = await signUp();
    const squad = await squadOf(mate);
    await hire(mate, squad);
    const path = `/squads/${squad}/coach/cards`;
    const written = await sql<{ id: string }>`
      insert into public.coach_member_notes (squad_id, member_id, coach_id, day, text, challenge_title)
      values (${squad}, ${mate.userId}, 'xiaohun', current_date, '早点睡', '早睡')
      returning id`.execute(db);
    const note = String(written.rows[0]?.id);
    await sql`insert into public.coach_member_note_deliveries (note_id) values (${note})`.execute(
      db,
    );
    await sql`insert into public.coach_challenge_completions (note_id, by)
      values (${note}, 'coach')`.execute(db);
    const cards = CardsBody.parse((await call({ method: 'GET', path, token: mate.token })).body);
    expect(ids(cards.stack)).toStrictEqual([
      `note:${note}`,
      `challenge:${note}`,
      `challengeDone:${note}`,
    ]);
    expect(cards.stack[1]).toMatchObject({ challenge: { title: '早睡', completedBy: 'coach' } });
    expect(cards.stack[2]).toMatchObject({
      kind: 'challengeDone',
      coach: speaker,
      challenge: { title: '早睡' },
    });
    const seen = await call({
      method: 'PUT',
      path: `${path}/challengeDone/${note}/seen`,
      token: mate.token,
    });
    expect(seen.status).toBe(200);
    const after = CardsBody.parse((await call({ method: 'GET', path, token: mate.token })).body);
    expect(ids(after.earlier)).toStrictEqual([`challengeDone:${note}`]);
    await fire(mate, squad);
  });

  it("shows only the day's newest challenge when a second note came that day", async () => {
    // An admin's delivered preview and the morning's wake both write a note with a challenge;
    // the newest one is the day's, so the older challenge doesn't show twice (Tracy, 2026-11-09).
    const mate = await signUp();
    const squad = await squadOf(mate);
    await hire(mate, squad);
    const path = `/squads/${squad}/coach/cards`;
    const note = async (title: string) => {
      const written = await sql<{ id: string }>`
        insert into public.coach_member_notes (squad_id, member_id, coach_id, day, text, challenge_title)
        values (${squad}, ${mate.userId}, 'xiaohun', current_date, '热身', ${title})
        returning id`.execute(db);
      const id = String(written.rows[0]?.id);
      await sql`insert into public.coach_member_note_deliveries (note_id) values (${id})`.execute(
        db,
      );
      return id;
    };
    const first = await note('热身');
    const second = await note('肩髋热身');
    const cards = CardsBody.parse((await call({ method: 'GET', path, token: mate.token })).body);
    const all = ids([...cards.stack, ...cards.earlier]);
    expect(all.filter((id) => id.startsWith('challenge:'))).toStrictEqual([`challenge:${second}`]);
    expect(all).toContain(`note:${first}`);
    expect(all).toContain(`note:${second}`);
    await fire(mate, squad);
  });

  it('still reads once the caller swiped cards of a kind that is no longer one', async () => {
    // Before 2026-11-09 the coach's replies and answers were cards too; their seen marks stay.
    const mate = await signUp();
    const squad = await squadOf(mate);
    await hire(mate, squad);
    await sql`insert into public.coach_card_seen (member_id, squad_id, kind, card_id)
      values (${mate.userId}, ${squad}, 'reply', '7'), (${mate.userId}, ${squad}, 'answer', '8')`.execute(
      db,
    );
    const path = `/squads/${squad}/coach/cards`;
    expect(await call({ method: 'GET', path, token: mate.token })).toMatchObject({ status: 200 });
    expect(await call({ method: 'GET', path: `${path}/earlier`, token: mate.token })).toMatchObject(
      { status: 200 },
    );
    await fire(mate, squad);
  });

  it('pages 以前 newest first, and keeps only the unseen ones when asked', async () => {
    const mate = await signUp();
    const squad = await squadOf(mate);
    // No coach now, so every card is 以前: 25 lines on 25 days, a second apart.
    for (let n = 0; n < 25; n += 1) {
      await sql`insert into public.coach_notes (squad_id, coach_id, day, text, at)
        values (${squad}, 'xiaohun', current_date - ${n}::int, ${`第${String(n)}句`},
          now() + make_interval(secs => ${25 - n}))`.execute(db);
    }
    const path = `/squads/${squad}/coach/cards/earlier`;
    const Page = z.object({
      cards: z.array(z.object({ text: z.string(), seen: z.boolean() }).loose()),
      next: z.string().optional(),
    });
    const first = Page.parse((await call({ method: 'GET', path, token: mate.token })).body);
    expect(first.cards).toHaveLength(20);
    expect(first.cards[0]).toMatchObject({ text: '第0句', seen: false });
    expect(first.next).toMatch(/^\d+~board:\d{4}-\d{2}-\d{2}$/u);
    const second = Page.parse(
      (
        await call({
          method: 'GET',
          path: `${path}?cursor=${encodeURIComponent(first.next ?? '')}`,
          token: mate.token,
        })
      ).body,
    );
    expect(second.cards.map((card) => card.text)).toStrictEqual([
      '第20句',
      '第21句',
      '第22句',
      '第23句',
      '第24句',
    ]);
    expect(second.next).toBeUndefined();

    const day = new Date(Date.now()).toISOString().slice(0, 10);
    expect(
      (
        await call({
          method: 'PUT',
          path: `/squads/${squad}/coach/cards/board/${day}/seen`,
          token: mate.token,
        })
      ).status,
    ).toBe(200);
    const unseen = Page.parse(
      (await call({ method: 'GET', path: `${path}?unseen=true`, token: mate.token })).body,
    );
    expect(unseen.cards.map((card) => card.text)).not.toContain('第0句');
    expect(unseen.cards.every((card) => !card.seen)).toBe(true);
    const odd = await call({ method: 'GET', path: `${path}?cursor=nope`, token: mate.token });
    expect(odd.status).toBe(400);
  });

  it('lists only the challenges when asked, every one since the caller joined, done ones marked', async () => {
    const [captain, mate] = [await signUp(), await signUp()];
    const squad = await squadOf(captain, mate);
    await hire(captain, squad);
    // Joined 60 days ago, so a challenge from 40 days ago is past 以前's 30 days but still theirs.
    await sql`update public.squad_members set joined_at = now() - interval '60 days'
      where squad_id = ${squad} and member_id = ${mate.userId}`.execute(db);
    const challenge = async (daysAgo: number, title: string) => {
      const written = await sql<{ id: string }>`
        insert into public.coach_member_notes
          (squad_id, member_id, coach_id, day, text, challenge_title, at)
        values (${squad}, ${mate.userId}, 'xiaohun', current_date - ${daysAgo}::int, '动一动', ${title},
          now() - make_interval(days => ${daysAgo}))
        returning id`.execute(db);
      const id = String(written.rows[0]?.id);
      // A card is dated by its delivery, so it is delivered then too.
      await sql`insert into public.coach_member_note_deliveries (note_id, at)
        values (${id}, now() - make_interval(days => ${daysAgo}))`.execute(db);
      return id;
    };
    const old = await challenge(40, '拉伸');
    await challenge(0, '喝水');
    await coachSaid(squad, { day: new Date().toISOString().slice(0, 10), text: '今天谁先动' });
    await sql`insert into public.coach_challenge_answers (note_id, answer) values (${old}, 'accepted')`.execute(
      db,
    );
    await sql`insert into public.coach_challenge_completions (note_id, by, at)
      values (${old}, 'member', now() - interval '40 days')`.execute(db);

    const Page = z.object({
      cards: z.array(z.object({ kind: z.string(), challenge: z.unknown().optional() }).loose()),
    });
    const path = `/squads/${squad}/coach/cards/earlier`;
    const only = Page.parse(
      (await call({ method: 'GET', path: `${path}?challenges=true`, token: mate.token })).body,
    );
    // Today's, still in the stack, and the one from 40 days ago, newest first; no 战术板 line.
    expect(only.cards.map((card) => card.kind)).toStrictEqual(['challenge', 'challenge']);
    expect(only.cards).toMatchObject([
      { challenge: { title: '喝水' } },
      { challenge: { title: '拉伸', completedBy: 'member' } },
    ]);
    // 以前 itself keeps to its 30 days and leaves the stack out.
    const all = Page.parse((await call({ method: 'GET', path, token: mate.token })).body);
    expect(all.cards.filter((card) => card.kind === 'challenge')).toStrictEqual([]);
    await fire(captain, squad);
  });

  it('keeps its place in 未读 when the card it ended on is seen, beside cards of the same moment', async () => {
    const mate = await signUp();
    const squad = await squadOf(mate);
    // 21 lines of one moment, as a morning note and its challenge are.
    for (let n = 0; n < 21; n += 1) {
      await sql`insert into public.coach_notes (squad_id, coach_id, day, text, at)
        values (${squad}, 'xiaohun', current_date - ${n}::int, ${`第${String(n)}句`},
          date_trunc('second', now()) + interval '5 seconds')`.execute(db);
    }
    const path = `/squads/${squad}/coach/cards/earlier?unseen=true`;
    const Page = z.object({
      cards: z.array(z.object({ id: z.string(), text: z.string() }).loose()),
      next: z.string().optional(),
    });
    const first = Page.parse((await call({ method: 'GET', path, token: mate.token })).body);
    expect(first.cards).toHaveLength(20);
    const ended = first.cards.at(-1)?.id ?? '';
    // Opened from 以前 before the next page: it leaves 未读.
    expect(
      (
        await call({
          method: 'PUT',
          path: `/squads/${squad}/coach/cards/board/${ended}/seen`,
          token: mate.token,
        })
      ).status,
    ).toBe(200);
    const second = Page.parse(
      (
        await call({
          method: 'GET',
          path: `${path}&cursor=${encodeURIComponent(first.next ?? '')}`,
          token: mate.token,
        })
      ).body,
    );
    const all = [...first.cards, ...second.cards].map((card) => card.text);
    expect(new Set(all).size).toBe(21);
    expect(second.next).toBeUndefined();
  });

  it('refuses anyone outside the squad and a kind it doesn’t know', async () => {
    const [captain, stranger] = [await signUp(), await signUp()];
    const squad = await squadOf(captain);
    const path = `/squads/${squad}/coach/cards`;
    const outside = await call({ method: 'GET', path, token: stranger.token });
    expect([outside.status, reason(outside)]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
    const marked = await call({
      method: 'PUT',
      path: `${path}/note/1/seen`,
      token: stranger.token,
    });
    expect(marked.status).toBe(403);
    expect((await call({ method: 'GET', path })).status).toBe(401);
    const odd = await call({ method: 'PUT', path: `${path}/poster/1/seen`, token: captain.token });
    expect(odd.status).toBe(400);
  });
});

describe('POST /squads/{squadId}/coach/letter', () => {
  // Writing and reading a letter is the coach module's to test, inside transactions it rolls
  // back, since it needs a second coach this shared database doesn't have.
  it('is asked for by the captain only, and is none without a change of coach', async () => {
    const [captain, mate] = [await signUp(), await signUp()];
    const squad = await squadOf(captain, mate);
    const path = `/squads/${squad}/coach/letter`;
    const byMate = await call({ method: 'POST', path, token: mate.token });
    expect([byMate.status, reason(byMate)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);
    await call({
      method: 'PUT',
      path: `/squads/${squad}/coach`,
      token: captain.token,
      body: { version: 1, coach: 'xiaohun' },
    });
    expect(await call({ method: 'POST', path, token: captain.token })).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: { version: 1, letter: null },
    });
    expect(
      await call({ method: 'GET', path: `/squads/${squad}/coach/activity`, token: mate.token }),
    ).not.toHaveProperty('body.letter');
    // Leave no squad with a coach: the coach's own tests count every squad that has one.
    const fired = await call({
      method: 'DELETE',
      path: `/squads/${squad}/coach`,
      token: captain.token,
    });
    expect(fired.status).toBe(200);
  });
});
