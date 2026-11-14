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
import {
  createNotices,
  createPostgresNoticeStore,
  createPostgresBroadcastStore,
} from '@wildcard/notices';
import {
  MemberId,
  SquadId,
  SquadName,
  createPostgresSquadStore,
  createSquads,
  randomInviteCodes,
} from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { sql } from 'kysely';
import { afterAll, afterEach, describe, expect, it } from 'vitest';
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
  placesOn,
  savedPlacesOn,
  weatherOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
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
import { catalogOn } from '../test-kit/public-routes.js';

/** The `index`th entry of a list a test made long enough. */
function nth<T>(list: readonly T[], index: number): T {
  const entry = list[index];
  if (entry === undefined) throw new Error(`No entry ${String(index)}.`);
  return entry;
}

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const members = createMembers({ store: createPostgresProfileStore(db) });
/** Whom the coach was asked to welcome, as each join's event reaches it. */
const welcomes: { readonly squad: string; readonly member: string }[] = [];
/** The moment a test fixes the app's week clock at; the real time otherwise. */
let fixedNow: Date | undefined;

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
  weather: weatherOn(db),
  ...unusedFeedback,
  scenes: scenesOn(db),
  switches: switchesOn(db),
  weeklyAwards: { ...unusedWeeklyAwards, clock: () => fixedNow ?? new Date() },
  unlocks: unusedUnlocks,
  gifts: unusedGifts,
  rewards: noRewards,
  coachHiring: unusedCoachHiring,
  coachActivity: unusedCoachActivity,
  coachMessages: unusedCoachMessages,
  coachLetters: unusedCoachLetters,
  notices: createNotices({
    store: createPostgresNoticeStore(db),
    broadcasts: createPostgresBroadcastStore(db),
    clock: () => new Date(),
  }),
  coachNames: () => Promise.reject(new Error('unused')),
  liveEvents: ignoredNotices.liveEvents,
  log: createLog(() => undefined),
  jobs: {
    ...noJobs,
    coach: {
      run: () => Promise.reject(new Error('unused')),
      preview: () => Promise.reject(new Error('unused')),
      answer: () => Promise.reject(new Error('unused')),
      checkedIn: () => Promise.reject(new Error('unused')),
      welcome: (asked) => {
        welcomes.push(asked);
        return Promise.resolve();
      },
    },
  },
  admin: adminOn(),
});

async function call({
  method,
  path,
  token,
  body,
  language,
}: {
  readonly method: string;
  readonly path: string;
  readonly token?: string | undefined;
  readonly body?: unknown;
  /** The app's language, as `Accept-Language`. */
  readonly language?: string | undefined;
}) {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  if (language !== undefined) headers['accept-language'] = language;
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

const create = (token: string, { id = randomUUID(), name }: { id?: string; name: unknown }) =>
  call({
    method: 'PUT',
    path: `/squads/${id}`,
    token,
    body: { version: 1, name, timeZone: 'America/New_York' },
  });

const SquadBody = z.object({
  id: z.uuid(),
  captain: z.uuid().nullable(),
  name: z.string(),
  inviteCode: z.string(),
  members: z.array(z.object({ userId: z.uuid(), joinedAt: z.string() })),
});
const SquadListBody = z.object({
  squads: z.array(SquadBody),
  lastSquad: z
    .object({ id: z.uuid(), name: z.string(), how: z.enum(['left', 'removed']) })
    .optional(),
});

/** A squad the member creates; its body. */
/** Turns the captain's OK to join off (入队需要审核), so friends join straight in. */
async function openToJoin(token: string, squad: string) {
  const turned = await call({
    method: 'PUT',
    path: `/squads/${squad}/join-approval`,
    token,
    body: { version: 1, required: false },
  });
  expect(turned.status).toBe(200);
}

/** A squad `token`'s member makes, which friends join without the captain's OK unless `needsOk`. */
async function newSquad(token: string, { name = '早八跑团', needsOk = false } = {}) {
  const { status, body } = await create(token, { name });
  expect(status).toBe(201);
  const squad = SquadBody.parse(body);
  if (!needsOk) await openToJoin(token, squad.id);
  return squad;
}

const reason = (response: { readonly body?: unknown }) =>
  z.object({ reason: z.string() }).safeParse(response.body).data?.reason;

const memberIds = (body: unknown) => SquadBody.parse(body).members.map(({ userId }) => userId);

describe('PUT /squads/{squadId}', () => {
  it('creates a squad with only a name, the caller its first member, and answers a retry', async () => {
    const me = await signUp();
    const id = randomUUID();
    const created = await create(me.token, { id, name: ' 早八跑团 ' });
    expect(created.status).toBe(201);
    const body = z
      .strictObject({
        version: z.literal(1),
        id: z.literal(id),
        name: z.literal('早八跑团'),
        inviteCode: z.string().regex(/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$/),
        createdAt: z.iso.datetime(),
        captain: z.literal(me.userId),
        members: z.tuple([
          z.strictObject({ userId: z.literal(me.userId), joinedAt: z.iso.datetime() }),
        ]),
      })
      .parse(created.body);

    const retry = await create(me.token, { id, name: '早八跑团' });
    expect([retry.status, retry.body]).toStrictEqual([200, body]);
    const conflict = await create(me.token, { id, name: '夜跑团' });
    expect([conflict.status, reason(conflict)]).toStrictEqual([409, 'SQUAD_ID_CONFLICT']);
  });

  it('refuses a blank or too long name, and a second squad', async () => {
    const me = await signUp();
    for (const name of ['  ', '跑'.repeat(21), '早八\n跑团', 3]) {
      const refused = await create(me.token, { name });
      expect([refused.status, reason(refused)]).toStrictEqual([400, 'REQUEST_INVALID']);
    }
    await newSquad(me.token);
    const second = await create(me.token, { name: '第二个' });
    expect([second.status, second.type, reason(second)]).toStrictEqual([
      400,
      'application/problem+json',
      'SQUAD_LIMIT_REACHED',
    ]);
  });

  it('answers 415 for a body not sent as JSON', async () => {
    const me = await signUp();
    const response = await app.request(`/squads/${randomUUID()}`, {
      method: 'PUT',
      headers: { authorization: `Bearer ${me.token}`, 'content-type': 'text/plain' },
      body: JSON.stringify({ version: 1, name: '早八跑团' }),
    });
    const body = z.object({ reason: z.string() }).parse(await response.json());
    expect([response.status, body.reason]).toStrictEqual([415, 'MEDIA_TYPE_UNSUPPORTED']);
  });

  it('asks a caller with no token to sign in', async () => {
    const refused = await call({
      method: 'PUT',
      path: `/squads/${randomUUID()}`,
      body: { version: 1, name: 'a', timeZone: 'America/New_York' },
    });
    expect([refused.status, reason(refused)]).toStrictEqual([401, 'AUTH_TOKEN_MISSING']);
  });
});

describe('joining by invite code', () => {
  it('previews, joins, and joining again changes nothing', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await newSquad(me.token, { name: '周末网球' });
    const typed = `${squad.inviteCode.slice(0, 4).toLowerCase()}-${squad.inviteCode.slice(4)}`;

    const preview = await call({
      method: 'GET',
      path: `/squad-invites/${typed}`,
      token: friend.token,
    });
    expect([preview.status, preview.body]).toStrictEqual([
      200,
      {
        version: 1,
        name: '周末网球',
        memberCount: 1,
        full: false,
        joined: false,
        needsApproval: false,
        daysPerMember: 3,
        looks: [],
      },
    ]);

    const joined = await call({
      method: 'POST',
      path: `/squad-invites/${typed}/accept`,
      token: friend.token,
    });
    expect(joined.status).toBe(201);
    expect(memberIds(joined.body)).toStrictEqual([me.userId, friend.userId]);
    const again = await call({
      method: 'POST',
      path: `/squad-invites/${squad.inviteCode}/accept`,
      token: friend.token,
    });
    expect([again.status, again.body]).toStrictEqual([200, joined.body]);
    // The squad's coach is asked to welcome the newcomer once, and never the creator.
    expect(welcomes.filter((each) => each.squad === squad.id)).toStrictEqual([
      { squad: squad.id, member: friend.userId },
    ]);
  });

  it.each(['ZZZZZZZZ', 'not-a-code!', '0O1IL0O1', 'K'.repeat(100)])(
    'answers 404 for %j',
    async (code) => {
      const me = await signUp();
      for (const response of [
        await call({ method: 'GET', path: `/squad-invites/${code}`, token: me.token }),
        await call({ method: 'POST', path: `/squad-invites/${code}/accept`, token: me.token }),
      ]) {
        expect([response.status, reason(response)]).toStrictEqual([404, 'INVITE_CODE_UNKNOWN']);
      }
    },
  );

  it('refuses a ninth member', async () => {
    const creator = await signUp();
    const squad = await newSquad(creator.token);
    const others = await Promise.all(Array.from({ length: 8 }, () => signUp()));
    const statuses = [];
    for (const member of others) {
      const joined = await call({
        method: 'POST',
        path: `/squad-invites/${squad.inviteCode}/accept`,
        token: member.token,
      });
      statuses.push(joined.status === 201 ? 'joined' : reason(joined));
    }
    expect(statuses).toStrictEqual([...Array<string>(7).fill('joined'), 'SQUAD_FULL']);
    const preview = await call({
      method: 'GET',
      path: `/squad-invites/${squad.inviteCode}`,
      token: others[7]?.token,
    });
    expect(preview.body).toMatchObject({ memberCount: 8, full: true, joined: false });
  });
});

describe('asking the captain to join (入队申请)', () => {
  const RequestBody = z.strictObject({
    version: z.literal(1),
    id: z.uuid(),
    squadId: z.uuid(),
    squadName: z.string(),
    note: z.string().optional(),
    askedAt: z.iso.datetime(),
    status: z.string(),
    answeredAt: z.iso.datetime().optional(),
    memberCount: z.int(),
    looks: z.array(z.object({ persona: z.string() }).loose()),
    captain: z.object({ nickname: z.string(), look: z.unknown() }).optional(),
  });
  const ask = (token: string, { inviteCode, note }: { inviteCode: string; note?: string }) =>
    call({
      method: 'POST',
      path: `/squad-invites/${inviteCode}/accept`,
      token,
      ...(note === undefined ? {} : { body: { version: 1, note } }),
    });
  const answer = (
    token: string,
    { squad, request, approve }: { squad: string; request: string; approve: boolean },
  ) =>
    call({
      method: 'PUT',
      path: `/squads/${squad}/join-requests/${request}`,
      token,
      body: { version: 1, approve },
    });
  const mine = async (token: string) => {
    const read = await call({ method: 'GET', path: '/me/join-request', token });
    expect(read.status).toBe(200);
    return z
      .strictObject({ version: z.literal(1), request: RequestBody.optional() })
      .parse(read.body).request;
  };
  const waiting = async (token: string, squad: string) => {
    const read = await call({ method: 'GET', path: `/squads/${squad}/join-requests`, token });
    return { status: read.status, body: read.body };
  };
  const membersOf = async (token: string, squad: string) =>
    memberIds((await call({ method: 'GET', path: `/squads/${squad}`, token })).body);
  const noticesOf = async (token: string, kind: string) =>
    z
      .object({ notices: z.array(z.object({ kind: z.string() }).loose()) })
      .parse((await call({ method: 'GET', path: '/me/notices', token })).body)
      .notices.filter((notice) => notice.kind === kind);
  const withCharacter = async (token: string, nickname: string) => {
    const saved = await call({
      method: 'PUT',
      path: '/me/profile',
      token,
      body: {
        version: 1,
        timeZone: 'UTC',
        character: { nickname, look: { persona: 'shy', variants: { body: 'lop' }, colors: {} } },
      },
    });
    expect(saved.status).toBe(200);
  };

  it('needs the captain’s OK by default, and the captain lets the member in', async () => {
    const [captain, asker] = [await signUp(), await signUp()];
    await withCharacter(asker.token, '小橘');
    const squad = await newSquad(captain.token, { name: '周三不练腿', needsOk: true });
    const setting = await call({
      method: 'GET',
      path: `/squads/${squad.id}/join-approval`,
      token: captain.token,
    });
    expect(setting.body).toStrictEqual({ version: 1, required: true });

    const preview = await call({
      method: 'GET',
      path: `/squad-invites/${squad.inviteCode}`,
      token: asker.token,
    });
    expect(preview.body).toMatchObject({ needsApproval: true, joined: false });
    const asked = await ask(asker.token, { inviteCode: squad.inviteCode, note: ' 我是小橘 ' });
    expect(asked.status).toBe(202);
    const request = RequestBody.parse(asked.body);
    expect(request).toMatchObject({
      squadId: squad.id,
      squadName: '周三不练腿',
      note: '我是小橘',
      status: 'waiting',
      memberCount: 1,
      looks: [],
    });
    // The captain made no character yet: none to show.
    expect([request.answeredAt, request.captain]).toStrictEqual([undefined, undefined]);
    // Asking again with the same note is the same request; the captain is told once.
    const again = await ask(asker.token, { inviteCode: squad.inviteCode, note: '我是小橘' });
    expect([again.status, RequestBody.parse(again.body).id]).toStrictEqual([202, request.id]);
    expect(await membersOf(captain.token, squad.id)).toStrictEqual([captain.userId]);
    expect(await mine(asker.token)).toStrictEqual(request);
    expect(await noticesOf(captain.token, 'joinRequest')).toMatchObject([
      { kind: 'joinRequest', joinRequest: request.id },
    ]);

    expect(await waiting(captain.token, squad.id)).toMatchObject({
      status: 200,
      body: {
        version: 1,
        requests: [
          {
            id: request.id,
            member: asker.userId,
            nickname: '小橘',
            look: { persona: 'shy' },
            note: '我是小橘',
          },
        ],
      },
    });

    const approved = await answer(captain.token, {
      squad: squad.id,
      request: request.id,
      approve: true,
    });
    expect(approved.status).toBe(200);
    expect(RequestBody.parse(approved.body)).toMatchObject({ id: request.id, status: 'approved' });
    expect(await membersOf(captain.token, squad.id)).toStrictEqual([captain.userId, asker.userId]);
    expect(welcomes.filter((each) => each.squad === squad.id)).toStrictEqual([
      { squad: squad.id, member: asker.userId },
    ]);
    expect(await noticesOf(asker.token, 'joinAnswered')).toMatchObject([
      { kind: 'joinAnswered', joinRequest: request.id, approved: true },
    ]);
    // Answering again the same way changes nothing; the other way is refused.
    expect(
      (await answer(captain.token, { squad: squad.id, request: request.id, approve: true })).status,
    ).toBe(200);
    const flipped = await answer(captain.token, {
      squad: squad.id,
      request: request.id,
      approve: false,
    });
    expect([flipped.status, reason(flipped)]).toStrictEqual([400, 'JOIN_REQUEST_ANSWERED']);
    expect(welcomes.filter((each) => each.squad === squad.id)).toHaveLength(1);
    expect((await waiting(captain.token, squad.id)).body).toMatchObject({ requests: [] });
    // Once in, opening the invite again is the squad.
    expect((await ask(asker.token, { inviteCode: squad.inviteCode })).status).toBe(200);
  });

  it('lets only the captain read and answer, and turns a member away', async () => {
    const [captain, mate, asker] = [await signUp(), await signUp(), await signUp()];
    await withCharacter(captain.token, '毛毛');
    const squad = await newSquad(captain.token);
    expect((await ask(mate.token, { inviteCode: squad.inviteCode })).status).toBe(201);
    const switched = await call({
      method: 'PUT',
      path: `/squads/${squad.id}/join-approval`,
      token: mate.token,
      body: { version: 1, required: true },
    });
    expect([switched.status, reason(switched)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);
    const turnedOn = await call({
      method: 'PUT',
      path: `/squads/${squad.id}/join-approval`,
      token: captain.token,
      body: { version: 1, required: true },
    });
    expect(turnedOn.body).toStrictEqual({ version: 1, required: true });

    const asked = await ask(asker.token, { inviteCode: squad.inviteCode });
    expect(asked.status).toBe(202);
    const request = RequestBody.parse(asked.body);
    expect(request).toMatchObject({
      memberCount: 2,
      looks: [{ persona: 'shy' }],
      captain: { nickname: '毛毛', look: { persona: 'shy' } },
    });
    expect(request.note).toBeUndefined();
    const byMate = await waiting(mate.token, squad.id);
    expect([byMate.status, reason(byMate)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);
    const answeredByMate = await answer(mate.token, {
      squad: squad.id,
      request: request.id,
      approve: true,
    });
    expect([answeredByMate.status, reason(answeredByMate)]).toStrictEqual([
      403,
      'NOT_SQUAD_CAPTAIN',
    ]);
    const unknown = await answer(captain.token, {
      squad: squad.id,
      request: randomUUID(),
      approve: true,
    });
    expect([unknown.status, reason(unknown)]).toStrictEqual([404, 'JOIN_REQUEST_UNKNOWN']);

    const declined = await answer(captain.token, {
      squad: squad.id,
      request: request.id,
      approve: false,
    });
    expect(RequestBody.parse(declined.body)).toMatchObject({ status: 'declined' });
    expect(await mine(asker.token)).toMatchObject({ id: request.id, status: 'declined' });
    expect(await membersOf(captain.token, squad.id)).toStrictEqual([captain.userId, mate.userId]);
    // A decline is told only in the app.
    expect(await noticesOf(asker.token, 'joinAnswered')).toStrictEqual([]);
    // They may ask again: a new request.
    const retry = await ask(asker.token, { inviteCode: squad.inviteCode });
    expect(RequestBody.parse(retry.body).id).not.toBe(request.id);
  });

  it('keeps one request waiting, withdrawn by the member or cancelled by joining elsewhere', async () => {
    const [ann, bo, asker] = [await signUp(), await signUp(), await signUp()];
    const first = await newSquad(ann.token, { name: '一', needsOk: true });
    const second = await newSquad(bo.token, { name: '二', needsOk: true });
    const tooLong = await ask(asker.token, { inviteCode: first.inviteCode, note: '长'.repeat(31) });
    expect([tooLong.status, reason(tooLong)]).toStrictEqual([400, 'REQUEST_INVALID']);

    const toFirst = RequestBody.parse(
      (await ask(asker.token, { inviteCode: first.inviteCode })).body,
    );
    const toSecond = RequestBody.parse(
      (await ask(asker.token, { inviteCode: second.inviteCode, note: '你好' })).body,
    );
    expect(await mine(asker.token)).toMatchObject({ id: toSecond.id, status: 'waiting' });
    expect((await waiting(ann.token, first.id)).body).toMatchObject({ requests: [] });
    const late = await answer(ann.token, { squad: first.id, request: toFirst.id, approve: true });
    expect([late.status, reason(late)]).toStrictEqual([400, 'JOIN_REQUEST_ANSWERED']);

    const withdrawn = await call({
      method: 'DELETE',
      path: '/me/join-request',
      token: asker.token,
    });
    expect(withdrawn.status).toBe(204);
    expect(
      (await call({ method: 'DELETE', path: '/me/join-request', token: asker.token })).status,
    ).toBe(204);
    expect(await mine(asker.token)).toMatchObject({ id: toSecond.id, status: 'withdrawn' });

    const third = RequestBody.parse(
      (await ask(asker.token, { inviteCode: second.inviteCode })).body,
    );
    await newSquad(asker.token, { name: '自己的' });
    expect(await mine(asker.token)).toMatchObject({ id: third.id, status: 'cancelled' });
    expect((await waiting(bo.token, second.id)).body).toMatchObject({ requests: [] });
  });

  it('cancels a waiting request once its squad ends', async () => {
    const [captain, asker] = [await signUp(), await signUp()];
    const squad = await newSquad(captain.token, { name: '散伙', needsOk: true });
    const asked = RequestBody.parse(
      (await ask(asker.token, { inviteCode: squad.inviteCode })).body,
    );
    const left = await call({
      method: 'DELETE',
      path: `/squads/${squad.id}/members/${captain.userId}`,
      token: captain.token,
    });
    expect(left.status).toBe(204);
    expect(await mine(asker.token)).toMatchObject({ id: asked.id, status: 'cancelled' });
  });

  it('lets a squad turn the OK off, so friends join straight in', async () => {
    const [captain, friend] = [await signUp(), await signUp()];
    const squad = await newSquad(captain.token, { name: '早八跑团', needsOk: true });
    const asked = RequestBody.parse(
      (await ask(friend.token, { inviteCode: squad.inviteCode })).body,
    );
    await openToJoin(captain.token, squad.id);
    // A request already waiting still waits for an answer.
    expect(await mine(friend.token)).toMatchObject({ id: asked.id, status: 'waiting' });
    const other = await signUp();
    expect((await ask(other.token, { inviteCode: squad.inviteCode })).status).toBe(201);
    expect(await mine(other.token)).toBeUndefined();
  });
});

describe('reading and leaving squads', () => {
  it('lists my squads, shows one only to its members, and leaving takes me out', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const mine = await newSquad(me.token, { name: '一' });
    const theirs = await newSquad(friend.token, { name: '二' });

    const list = await call({ method: 'GET', path: '/me/squads', token: me.token });
    expect(list.status).toBe(200);
    expect(SquadListBody.parse(list.body).squads.map(({ name }) => name)).toStrictEqual(['一']);
    expect(SquadListBody.parse(list.body).lastSquad).toBeUndefined();

    const seen = await call({ method: 'GET', path: `/squads/${mine.id}`, token: friend.token });
    expect([seen.status, reason(seen)]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
    const missing = await call({
      method: 'GET',
      path: `/squads/${randomUUID()}`,
      token: friend.token,
    });
    expect([missing.status, reason(missing)]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
    for (const [method, path] of [
      ['GET', '/squads/not-a-uuid'],
      ['DELETE', `/squads/not-a-uuid/members/${me.userId}`],
      ['DELETE', `/squads/${theirs.id}/members/me`],
    ] as const) {
      const malformed = await call({ method, path, token: friend.token });
      expect([malformed.status, reason(malformed)]).toStrictEqual([400, 'REQUEST_INVALID']);
    }
    expect(
      (await call({ method: 'GET', path: `/squads/${mine.id}`, token: me.token })).status,
    ).toBe(200);

    const left = await call({
      method: 'DELETE',
      path: `/squads/${mine.id}/members/${me.userId}`,
      token: me.token,
    });
    expect([left.status, left.body]).toStrictEqual([204, undefined]);
    const leftAgain = await call({
      method: 'DELETE',
      path: `/squads/${mine.id}/members/${me.userId}`,
      token: me.token,
    });
    expect(leftAgain.status).toBe(204);
    const after = await call({ method: 'GET', path: '/me/squads', token: me.token });
    expect(SquadListBody.parse(after.body)).toMatchObject({
      squads: [],
      lastSquad: { id: mine.id, name: '一', how: 'left' },
    });
    const gone = await call({ method: 'GET', path: `/squads/${mine.id}`, token: me.token });
    expect(reason(gone)).toBe('SQUAD_NOT_JOINED');
  });
});

describe('the captain’s settings', () => {
  /** A squad of `count` members, the first its captain. */
  async function squadOf(count: number) {
    const people = await Promise.all(Array.from({ length: count }, () => signUp()));
    const [captain, rest] = [nth(people, 0), people.slice(1)];
    const squad = await newSquad(captain.token);
    for (const member of rest) {
      const joined = await call({
        method: 'POST',
        path: `/squad-invites/${squad.inviteCode}/accept`,
        token: member.token,
      });
      expect(joined.status).toBe(201);
    }
    return { squad, people };
  }

  it('lets only the captain rename the squad', async () => {
    const { squad, people } = await squadOf(2);
    const [ann, bo] = [nth(people, 0), nth(people, 1)];
    expect(squad.captain).toBe(ann.userId);
    const path = `/squads/${squad.id}/name`;
    const renamed = await call({
      method: 'PUT',
      path,
      token: ann.token,
      body: { version: 1, name: ' 夜跑团 ' },
    });
    expect([renamed.status, SquadBody.parse(renamed.body).name]).toStrictEqual([200, '夜跑团']);
    const refused = await call({
      method: 'PUT',
      path,
      token: bo.token,
      body: { version: 1, name: '乱改' },
    });
    expect([refused.status, reason(refused)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);
    const tooLong = await call({
      method: 'PUT',
      path,
      token: ann.token,
      body: { version: 1, name: '跑'.repeat(21) },
    });
    expect(tooLong.status).toBe(400);
  });

  it('hands the captaincy on, and the new captain removes members', async () => {
    const { squad, people } = await squadOf(3);
    const [ann, bo, cy] = [nth(people, 0), nth(people, 1), nth(people, 2)];
    const captainPath = `/squads/${squad.id}/captain`;
    const stranger = await call({
      method: 'PUT',
      path: captainPath,
      token: ann.token,
      body: { version: 1, member: randomUUID() },
    });
    expect([stranger.status, reason(stranger)]).toStrictEqual([404, 'SQUAD_MEMBER_UNKNOWN']);
    const handed = await call({
      method: 'PUT',
      path: captainPath,
      token: ann.token,
      body: { version: 1, member: bo.userId },
    });
    expect([handed.status, SquadBody.parse(handed.body).captain]).toStrictEqual([200, bo.userId]);

    const byAnn = await call({
      method: 'DELETE',
      path: `/squads/${squad.id}/members/${cy.userId}`,
      token: ann.token,
    });
    expect([byAnn.status, reason(byAnn)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);
    const byBo = await call({
      method: 'DELETE',
      path: `/squads/${squad.id}/members/${cy.userId}`,
      token: bo.token,
    });
    expect(byBo.status).toBe(204);
    const seen = await call({ method: 'GET', path: `/squads/${squad.id}`, token: bo.token });
    expect(memberIds(seen.body)).toStrictEqual([ann.userId, bo.userId]);
    const removed = await call({ method: 'GET', path: '/me/squads', token: cy.token });
    expect(SquadListBody.parse(removed.body)).toMatchObject({
      squads: [],
      lastSquad: { id: squad.id, name: squad.name, how: 'removed' },
    });
    const elsewhere = await newSquad(cy.token, { name: '新队' });
    const rejoined = SquadListBody.parse(
      (await call({ method: 'GET', path: '/me/squads', token: cy.token })).body,
    );
    expect([rejoined.squads.map(({ id }) => id), rejoined.lastSquad]).toStrictEqual([
      [elsewhere.id],
      undefined,
    ]);

    await call({
      method: 'DELETE',
      path: `/squads/${squad.id}/members/${bo.userId}`,
      token: bo.token,
    });
    const after = await call({ method: 'GET', path: `/squads/${squad.id}`, token: ann.token });
    expect(SquadBody.parse(after.body).captain).toBe(ann.userId);
  });
});

describe('the squad’s scene', () => {
  const SceneBody = z.object({
    week: z.string(),
    scene: z.string(),
    sceneId: z.string(),
    takeover: z.boolean(),
    pickers: z.object({ by: z.string(), members: z.array(z.uuid()) }),
    picked: z
      .object({ scene: z.string(), sceneId: z.string(), by: z.uuid().nullable() })
      .nullable(),
    canPick: z.boolean(),
    scenes: z.array(z.object({ scene: z.string(), weeksAgo: z.int().nullable() })),
    options: z.array(z.object({ sceneId: z.string(), weeksAgo: z.int().nullable() })),
  });

  it('starts on the gym, and lets the captain pick once when nobody won the crown', async () => {
    const [ann, bo] = [await signUp(), await signUp()];
    const squad = await newSquad(ann.token);
    await call({
      method: 'POST',
      path: `/squad-invites/${squad.inviteCode}/accept`,
      token: bo.token,
    });

    const first = await call({
      method: 'GET',
      path: `/squads/${squad.id}/scene`,
      token: ann.token,
    });
    const scene = SceneBody.parse(first.body);
    expect(scene).toMatchObject({
      scene: 'gym',
      pickers: { by: 'captain', members: [ann.userId] },
      picked: null,
      canPick: true,
      scenes: [
        { scene: 'track', weeksAgo: null },
        { scene: 'pool', weeksAgo: null },
        { scene: 'gym', weeksAgo: 0 },
        { scene: 'tennis', weeksAgo: null },
        { scene: 'climbing', weeksAgo: null },
      ],
    });
    expect(scene.sceneId).toBe('gym');
    expect(scene.takeover).toBe(false);
    // The winter 雪场 joins the options only inside its window, so only the all-year ones are fixed.
    expect(scene.options.filter(({ sceneId }) => sceneId !== 'ski')).toStrictEqual([
      { sceneId: 'track', weeksAgo: null },
      { sceneId: 'pool', weeksAgo: null },
      { sceneId: 'gym', weeksAgo: 0 },
      { sceneId: 'tennis', weeksAgo: null },
      { sceneId: 'climbing', weeksAgo: null },
    ]);
    const forBo = await call({ method: 'GET', path: `/squads/${squad.id}/scene`, token: bo.token });
    expect(SceneBody.parse(forBo.body).canPick).toBe(false);

    const path = `/squads/${squad.id}/weeks/${scene.week}/scene`;
    const notBo = await call({
      method: 'PUT',
      path,
      token: bo.token,
      body: { version: 1, scene: 'gym' },
    });
    expect([notBo.status, reason(notBo)]).toStrictEqual([403, 'NOT_SCENE_PICKER']);
    const unlisted = await call({
      method: 'PUT',
      path,
      token: ann.token,
      body: { version: 1, scene: 'moon' },
    });
    expect([unlisted.status, reason(unlisted)]).toStrictEqual([400, 'SCENE_NOT_OPEN']);
    const picked = await call({
      method: 'PUT',
      path,
      token: ann.token,
      body: { version: 1, scene: 'pool' },
    });
    expect(picked.status).toBe(201);
    expect(SceneBody.parse(picked.body)).toMatchObject({
      scene: 'pool',
      sceneId: 'pool',
      picked: { scene: 'pool', sceneId: 'pool', by: ann.userId },
      canPick: false,
    });
    const retry = await call({
      method: 'PUT',
      path,
      token: ann.token,
      body: { version: 1, scene: 'pool' },
    });
    expect(retry.status).toBe(200);
    const again = await call({
      method: 'PUT',
      path,
      token: ann.token,
      body: { version: 1, scene: 'gym' },
    });
    expect([again.status, reason(again)]).toStrictEqual([409, 'SCENE_ALREADY_PICKED']);
    // Bo finds the move in 通知, once however often it was sent; Ann, who made it, doesn't.
    const noticesOf = async (token: string) =>
      z
        .object({ notices: z.array(z.record(z.string(), z.unknown())) })
        .parse((await call({ method: 'GET', path: '/me/notices', token })).body)
        .notices.map(({ kind, squadId, scene: moved, by }) => ({
          kind,
          squadId,
          scene: moved,
          by,
        }));
    expect(await noticesOf(bo.token)).toStrictEqual([
      { kind: 'sceneMoved', squadId: squad.id, scene: 'pool', by: ann.userId },
    ]);
    expect(await noticesOf(ann.token)).toStrictEqual([]);

    const nextWeek = new Date(Date.parse(scene.week) + 7 * 86_400_000).toISOString().slice(0, 10);
    const closed = await call({
      method: 'PUT',
      path: `/squads/${squad.id}/weeks/${nextWeek}/scene`,
      token: ann.token,
      body: { version: 1, scene: 'gym' },
    });
    expect([closed.status, reason(closed)]).toStrictEqual([400, 'SCENE_WEEK_CLOSED']);
    const stranger = await signUp();
    const hidden = await call({
      method: 'GET',
      path: `/squads/${squad.id}/scene`,
      token: stranger.token,
    });
    expect([hidden.status, reason(hidden)]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
  });
});

describe('GET /public/squad-invites/{inviteCode}', () => {
  /** A lookup from the web invite page, as a client at `address`. */
  async function lookUp(code: string, address: string) {
    const response = await app.request(`/public/squad-invites/${code}`, {
      // Cloud Run adds the connecting address last; the first entry is the client's own claim.
      headers: { 'x-forwarded-for': `198.51.100.1, ${address}` },
    });
    const text = await response.text();
    return {
      status: response.status,
      cacheControl: response.headers.get('cache-control'),
      retryAfter: response.headers.get('retry-after'),
      body: z.unknown().parse(JSON.parse(text)),
    };
  }

  it('shows anyone the name, size, whether it is full and the looks, and nothing about who is in it', async () => {
    const looks = [
      { persona: 'drama', variants: { body: 'peach', hair: 'bob' }, colors: { hair: '#3B2A20' } },
      { persona: 'shy', variants: { body: 'lop' }, colors: {} },
    ];
    const [creator, notYet, joiner] = [await signUp(), await signUp(), await signUp()];
    for (const [member, character] of [
      [creator, { nickname: '安安', look: looks[0] }],
      [notYet, undefined],
      [joiner, { nickname: '小周', look: looks[1] }],
    ] as const) {
      const saved = await call({
        method: 'PUT',
        path: '/me/profile',
        token: member.token,
        body: { version: 1, timeZone: 'UTC', character },
      });
      expect(saved.status).toBe(200);
    }
    const squad = await newSquad(creator.token, { name: '周末网球' });
    for (const member of [notYet, joiner]) {
      const joined = await call({
        method: 'POST',
        path: `/squad-invites/${squad.inviteCode}/accept`,
        token: member.token,
      });
      expect(joined.status).toBe(201);
    }
    const typed = `${squad.inviteCode.slice(0, 4).toLowerCase()}-${squad.inviteCode.slice(4)}`;
    // In the order they joined; no nicknames or ids, and nothing for one with no character yet.
    expect(await lookUp(typed, '203.0.113.10')).toStrictEqual({
      status: 200,
      cacheControl: 'no-store',
      retryAfter: null,
      body: { version: 1, name: '周末网球', memberCount: 3, full: false, daysPerMember: 3, looks },
    });
    // A signed-in newcomer's join screen gets the same looks, before joining.
    const newcomer = await signUp();
    const preview = await call({
      method: 'GET',
      path: `/squad-invites/${typed}`,
      token: newcomer.token,
    });
    expect([preview.status, preview.body]).toStrictEqual([
      200,
      {
        version: 1,
        name: '周末网球',
        memberCount: 3,
        full: false,
        joined: false,
        needsApproval: false,
        daysPerMember: 3,
        looks,
      },
    ]);
  });

  it('answers an unknown code and one that can’t be a code alike', async () => {
    for (const code of ['ZZZZZZZZ', 'not-a-code!']) {
      const response = await lookUp(code, '203.0.113.11');
      expect([response.status, reason(response)]).toStrictEqual([404, 'INVITE_CODE_UNKNOWN']);
    }
  });

  it('lets the website read the answer from the browser, refusals included, and no other site', async () => {
    const from = (origin: string) =>
      app.request('/public/squad-invites/ZZZZZZZZ', {
        headers: { origin, 'x-forwarded-for': '203.0.113.14' },
      });
    const site = await from('https://wildcardsquad.com');
    expect([site.status, site.headers.get('access-control-allow-origin')]).toStrictEqual([
      404,
      'https://wildcardsquad.com',
    ]);
    const other = await from('https://example.com');
    expect([other.status, other.headers.get('access-control-allow-origin')]).toStrictEqual([
      404,
      null,
    ]);
  });

  it('refuses a client after 3 lookups, whatever it claims to be, and lets others through', async () => {
    const statuses = [];
    for (let attempt = 0; attempt < 4; attempt += 1) {
      statuses.push((await lookUp('ZZZZZZZZ', '203.0.113.12')).status);
    }
    expect(statuses).toStrictEqual([404, 404, 404, 429]);
    const refused = await lookUp('ZZZZZZZZ', '203.0.113.12');
    expect([refused.status, reason(refused)]).toStrictEqual([429, 'REQUESTS_TOO_FREQUENT']);
    expect(Number(refused.retryAfter)).toBeGreaterThan(590);
    expect((await lookUp('ZZZZZZZZ', '203.0.113.13')).status).toBe(404);
  });
});

/** A valid invite code made from a uuid's hex digits, to write a squad straight to the table. */
const inviteCodeFor = (id: string) =>
  Array.from(id.replaceAll('-', '').slice(0, 8), (digit) =>
    '23456789ABCDEFGH'.charAt(Number.parseInt(digit, 16)),
  ).join('');

describe('the squad’s weekly goal', () => {
  const goalOf = (token: string, squad: string) =>
    call({ method: 'GET', path: `/squads/${squad}/weekly-goal`, token });
  const setGoal = (token: string, change: { squad: string; daysPerMember: unknown }) =>
    call({
      method: 'PUT',
      path: `/squads/${change.squad}/weekly-goal`,
      token,
      body: { version: 1, daysPerMember: change.daysPerMember },
    });

  it('takes the creator’s pick, shows it on the invite, and lets only the captain change it from next week', async () => {
    const [me, friend, outsider] = [await signUp(), await signUp(), await signUp()];
    const id = randomUUID();
    const created = await call({
      method: 'PUT',
      path: `/squads/${id}`,
      token: me.token,
      body: { version: 1, name: '练得多', daysPerMember: 5, timeZone: 'America/New_York' },
    });
    expect(created.status).toBe(201);
    const { inviteCode } = SquadBody.parse(created.body);
    const invite = await call({ method: 'GET', path: `/public/squad-invites/${inviteCode}` });
    expect(invite.body).toMatchObject({ memberCount: 1, daysPerMember: 5 });
    await openToJoin(me.token, id);
    await call({
      method: 'POST',
      path: `/squad-invites/${inviteCode}/accept`,
      token: friend.token,
    });

    // A new squad has no finished week to average yet.
    expect(await goalOf(friend.token, id)).toStrictEqual({
      status: 200,
      type: 'application/json',
      body: { version: 1, daysPerMember: 5, nextDaysPerMember: 5, canChange: false, recent: null },
    });
    const refused = await setGoal(friend.token, { squad: id, daysPerMember: 4 });
    expect([refused.status, reason(refused)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);
    const outside = await goalOf(outsider.token, id);
    expect([outside.status, reason(outside)]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
    for (const daysPerMember of [0, 8, 2.5, '4']) {
      const invalid = await setGoal(me.token, { squad: id, daysPerMember });
      expect([invalid.status, reason(invalid)]).toStrictEqual([400, 'REQUEST_INVALID']);
    }

    const changed = await setGoal(me.token, { squad: id, daysPerMember: 4 });
    expect(changed.body).toStrictEqual({
      version: 1,
      daysPerMember: 5,
      nextDaysPerMember: 4,
      canChange: true,
      recent: null,
    });
    // This week's goal on the home stays: 5 a member, times 2.
    const today = await call({ method: 'GET', path: `/squads/${id}/today`, token: me.token });
    expect(today.body).toMatchObject({ squadWeek: { plannedDays: 10, daysPerMember: 5 } });
  });

  it('averages the 训练 per member over up to 4 finished weeks', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const DAY = 86_400_000;
    // This week's Monday, as a member with no time zone (UTC) has it.
    const today = new Date();
    const monday = new Date(
      Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()) -
        ((today.getUTCDay() + 6) % 7) * DAY,
    );
    const dayOf = (offset: number) =>
      new Date(monday.getTime() + offset * DAY).toISOString().slice(0, 10);
    // Made 2 weeks and a day ago: its first week (from that Sunday) and last week finished.
    const id = randomUUID();
    const made = new Date(monday.getTime() - 8 * DAY).toISOString();
    await sql`insert into public.squads (id, name, invite_code, created_by, captain_id, created_at)
      values (${id}, '老队', ${inviteCodeFor(id)}, ${me.userId}, ${me.userId}, ${made})`.execute(
      db,
    );
    for (const [member, at] of [
      [me.userId, made],
      // My friend joined last Monday.
      [friend.userId, new Date(monday.getTime() - 7 * DAY).toISOString()],
    ] as const) {
      await sql`insert into public.squad_members (squad_id, member_id, joined_at)
        values (${id}, ${member}, ${at})`.execute(db);
      await sql`insert into public.squad_membership_events (squad_id, member_id, kind, actor_id, at)
        values (${id}, ${member}, 'joined', ${member}, ${at})`.execute(db);
    }
    const trained = async (member: string, day: string) => {
      const checkIn = randomUUID();
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${checkIn}, ${member}, ${day}, ${`${day}T12:00:00.000Z`}, 'trained',
          '{"version":1,"sport":"run"}')`.execute(db);
      await sql`insert into public.check_in_squads (check_in_id, squad_id, position)
        values (${checkIn}, ${id}, 1)`.execute(db);
    };
    // The first week (me alone): 1. Last week: me 4 (twice on one day), my friend 2.
    await trained(me.userId, dayOf(-8));
    for (const offset of [-7, -7, -6, -5]) await trained(me.userId, dayOf(offset));
    for (const offset of [-4, -3]) await trained(friend.userId, dayOf(offset));
    // This week doesn't count yet.
    await trained(friend.userId, dayOf(0));

    const goal = await goalOf(me.token, id);
    // (1 / 1 + 6 / 2) / 2 = 2.
    expect(goal.body).toMatchObject({ daysPerMember: 3, recent: { weeks: 2, daysPerMember: 2 } });
  });

  it('keeps the recent average at 7 a member, the highest goal, however often they trained', async () => {
    const me = await signUp();
    const DAY = 86_400_000;
    const today = new Date();
    const monday = new Date(
      Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()) -
        ((today.getUTCDay() + 6) % 7) * DAY,
    );
    const lastWeek = (offset: number) =>
      new Date(monday.getTime() + (offset - 7) * DAY).toISOString().slice(0, 10);
    // Made 8 days ago: only last week finished.
    const id = randomUUID();
    const made = new Date(monday.getTime() - 7 * DAY).toISOString();
    await sql`insert into public.squads (id, name, invite_code, created_by, captain_id, created_at)
      values (${id}, '双练队', ${inviteCodeFor(id)}, ${me.userId}, ${me.userId}, ${made})`.execute(
      db,
    );
    await sql`insert into public.squad_members (squad_id, member_id, joined_at)
      values (${id}, ${me.userId}, ${made})`.execute(db);
    await sql`insert into public.squad_membership_events (squad_id, member_id, kind, actor_id, at)
      values (${id}, ${me.userId}, 'joined', ${me.userId}, ${made})`.execute(db);
    // Twice a day, every day of last week: 14.
    for (let day = 0; day < 7; day += 1) {
      for (const hour of ['08', '18']) {
        const checkIn = randomUUID();
        const on = lastWeek(day);
        await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
          values (${checkIn}, ${me.userId}, ${on}, ${`${on}T${hour}:00:00.000Z`}, 'trained',
            '{"version":1,"sport":"run"}')`.execute(db);
        await sql`insert into public.check_in_squads (check_in_id, squad_id, position)
          values (${checkIn}, ${id}, 1)`.execute(db);
      }
    }

    const goal = await goalOf(me.token, id);
    expect(goal.body).toMatchObject({ recent: { weeks: 1, daysPerMember: 7 } });
  });
});

describe('the squad’s time zone', () => {
  const zoneOf = (token: string, squad: string) =>
    call({ method: 'GET', path: `/squads/${squad}/time-zone`, token });
  const setZone = (token: string, change: { squad: string; timeZone: unknown }) =>
    call({
      method: 'PUT',
      path: `/squads/${change.squad}/time-zone`,
      token,
      body: { version: 1, timeZone: change.timeZone },
    });

  it('takes the creator’s pick, and lets only the captain change it', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const id = randomUUID();
    const created = await call({
      method: 'PUT',
      path: `/squads/${id}`,
      token: me.token,
      body: { version: 1, name: '台北队', timeZone: 'Asia/Taipei' },
    });
    expect(created.status).toBe(201);
    await openToJoin(me.token, id);
    await call({
      method: 'POST',
      path: `/squad-invites/${SquadBody.parse(created.body).inviteCode}/accept`,
      token: friend.token,
    });
    expect((await zoneOf(friend.token, id)).body).toStrictEqual({
      version: 1,
      timeZone: 'Asia/Taipei',
      nextTimeZone: 'Asia/Taipei',
      canChange: false,
    });
    const refused = await setZone(friend.token, { squad: id, timeZone: 'America/New_York' });
    expect([refused.status, reason(refused)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);
    const unknown = await setZone(me.token, { squad: id, timeZone: 'Mars/Olympus' });
    expect([unknown.status, reason(unknown)]).toStrictEqual([400, 'TIME_ZONE_UNKNOWN']);
    // Node reads a zone in any case; Postgres only as it spells it.
    const lowercase = await setZone(me.token, { squad: id, timeZone: 'asia/tokyo' });
    expect([lowercase.status, reason(lowercase)]).toStrictEqual([400, 'TIME_ZONE_UNKNOWN']);
    const lowercaseSquad = await call({
      method: 'PUT',
      path: `/squads/${randomUUID()}`,
      token: (await signUp()).token,
      body: { version: 1, name: '东京队', timeZone: 'asia/tokyo' },
    });
    expect([lowercaseSquad.status, reason(lowercaseSquad)]).toStrictEqual([
      400,
      'TIME_ZONE_UNKNOWN',
    ]);
  });

  describe('on a fixed clock', () => {
    afterEach(() => {
      fixedNow = undefined;
    });
    const squadModule = createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent: () => Promise.resolve(true),
    });
    async function taipeiSquad() {
      const me = await signUp();
      const { squad } = await squadModule.create({
        week: '2026-11-02',
        id: SquadId.parse(randomUUID()),
        creator: MemberId.parse(me.userId),
        name: SquadName.parse('台北队'),
        timeZone: 'Asia/Taipei',
      });
      return { me, id: squad.id };
    }

    it('counts a change at once before this week’s Sunday 8pm on either clock', async () => {
      const { me, id } = await taipeiSquad();
      // Sunday 2026-11-08 19:59:59.999 in Taipei, 03:59 in Los Angeles.
      fixedNow = new Date('2026-11-08T11:59:59.999Z');
      const changed = await setZone(me.token, { squad: id, timeZone: 'America/Los_Angeles' });
      expect(changed.body).toStrictEqual({
        version: 1,
        timeZone: 'America/Los_Angeles',
        nextTimeZone: 'America/Los_Angeles',
        canChange: true,
      });
      expect((await zoneOf(me.token, id)).body).toStrictEqual(changed.body);
    });

    it('counts a change from next week once the week froze on the old clock', async () => {
      const { me, id } = await taipeiSquad();
      // Sunday 2026-11-08 20:00 in Taipei: the week froze there; 04:00 in Los Angeles.
      fixedNow = new Date('2026-11-08T12:00:00Z');
      const waiting = {
        version: 1,
        timeZone: 'Asia/Taipei',
        nextTimeZone: 'America/Los_Angeles',
        canChange: true,
      };
      const changed = await setZone(me.token, { squad: id, timeZone: 'America/Los_Angeles' });
      expect(changed.body).toStrictEqual(waiting);
      expect((await zoneOf(me.token, id)).body).toStrictEqual(waiting);
      // Once Los Angeles's Monday begins, the new zone is this week's.
      fixedNow = new Date('2026-11-09T08:00:00Z');
      expect((await zoneOf(me.token, id)).body).toStrictEqual({
        ...waiting,
        timeZone: 'America/Los_Angeles',
      });
    });
  });

  it('refuses a squad made without a time zone', async () => {
    const me = await signUp();
    const refused = await call({
      method: 'PUT',
      path: `/squads/${randomUUID()}`,
      token: me.token,
      body: { version: 1, name: '早八跑团' },
    });
    expect([refused.status, reason(refused)]).toStrictEqual([400, 'REQUEST_INVALID']);
  });
});

describe('the squad’s language', () => {
  const languageOf = (token: string, { squad, language }: { squad: string; language?: string }) =>
    call({ method: 'GET', path: `/squads/${squad}/language`, token, language });
  const setLanguage = (token: string, change: { squad: string; language: unknown }) =>
    call({
      method: 'PUT',
      path: `/squads/${change.squad}/language`,
      token,
      body: { version: 1, language: change.language },
    });

  it('reads the captain’s app language until the captain picks one, which only the captain may', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await newSquad(me.token);
    await call({
      method: 'POST',
      path: `/squad-invites/${squad.inviteCode}/accept`,
      token: friend.token,
    });
    // No app language heard yet: Simplified Chinese.
    expect((await languageOf(friend.token, { squad: squad.id })).body).toStrictEqual({
      version: 1,
      language: 'zh-Hans',
      canChange: false,
    });
    // The captain's app speaks 繁體 (kept with their profile); a member's own doesn't count.
    const saved = await call({
      method: 'PUT',
      path: '/me/profile',
      token: me.token,
      body: { version: 1, timeZone: 'Asia/Taipei' },
      language: 'zh-Hant',
    });
    expect(saved.status).toBe(200);
    // Heard before the profile existed, so heard again.
    await languageOf(me.token, { squad: squad.id, language: 'zh-Hant' });
    expect(
      (await languageOf(friend.token, { squad: squad.id, language: 'en' })).body,
    ).toMatchObject({
      language: 'zh-Hant',
    });

    const refused = await setLanguage(friend.token, { squad: squad.id, language: 'en' });
    expect([refused.status, reason(refused)]).toStrictEqual([403, 'NOT_SQUAD_CAPTAIN']);
    const unknown = await setLanguage(me.token, { squad: squad.id, language: 'fr' });
    expect(unknown.status).toBe(400);
    const changed = await setLanguage(me.token, { squad: squad.id, language: 'en' });
    expect(changed.body).toStrictEqual({ version: 1, language: 'en', canChange: true });
    // Picked, it no longer follows the captain's app.
    expect(
      (await languageOf(me.token, { squad: squad.id, language: 'zh-Hans' })).body,
    ).toMatchObject({
      language: 'en',
    });
    const outsider = await signUp();
    const notJoined = await languageOf(outsider.token, { squad: squad.id });
    expect([notJoined.status, reason(notJoined)]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
  });
});
