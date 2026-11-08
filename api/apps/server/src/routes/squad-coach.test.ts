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
  scenesOn,
  switchesOn,
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import {
  unusedWeeklyAwards,
  unusedWeekSummaryWords,
  unusedUnlocks,
  unusedGifts,
  ignoredNotices,
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
  scenes: scenesOn(db),
  switches: switchesOn(db),
  weeklyAwards: unusedWeeklyAwards,
  unlocks: unusedUnlocks,
  gifts: unusedGifts,
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
    await sql`insert into public.coach_answers (squad_id, check_in_id, comment_id, coach_id, text)
      values (${squad}, ${run}, ${asked}, 'xiaohun', '那就再跑一圈')`.execute(db);

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
        { checkInId: run, commentId: asked, coach: speaker, text: '那就再跑一圈', at: 'at' },
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
