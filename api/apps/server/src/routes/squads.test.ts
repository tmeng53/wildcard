import { randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createOffSender, createPostgresDeviceStore, createPush } from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createMemoryRateLimit } from '../adapters/memory-rate-limit.js';
import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import { adminOn, config, signUp, aiConsentOn } from '../test-kit/local-supabase.js';

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
  publicRoutes: {
    proxyHops: 1,
    inviteLookups: createMemoryRateLimit({ limit: 3, windowSeconds: 600, clock: () => new Date() }),
  },
  photos,
  checkIns: createCheckIns({
    store: createPostgresCheckInStore(db),
    membership: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent: () => Promise.resolve(true),
    }),
    reactions: createPostgresReactionStore(db),
    plans: createPostgresWeeklyPlanStore(db),
    photos,
    calendarOf: memberCalendar(members),
    clock: () => new Date(),
  }),
  weeklyPlans: createWeeklyPlans({
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
  push: createPush({ store: createPostgresDeviceStore(db), sender: createOffSender() }),
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  aiConsent: aiConsentOn(db),
  log: createLog(() => undefined),
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

const create = (token: string, { id = randomUUID(), name }: { id?: string; name: unknown }) =>
  call({ method: 'PUT', path: `/squads/${id}`, token, body: { version: 1, name } });

const SquadBody = z.object({
  id: z.uuid(),
  name: z.string(),
  inviteCode: z.string(),
  members: z.array(z.object({ userId: z.uuid(), joinedAt: z.string() })),
});
const SquadListBody = z.object({ squads: z.array(SquadBody) });

/** A squad the member creates; its body. */
async function newSquad(token: string, name = '早八跑团') {
  const { status, body } = await create(token, { name });
  expect(status).toBe(201);
  return SquadBody.parse(body);
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

  it('refuses a blank or too long name, and a fourth squad', async () => {
    const me = await signUp();
    for (const name of ['  ', '跑'.repeat(21), '早八\n跑团', 3]) {
      const refused = await create(me.token, { name });
      expect([refused.status, reason(refused)]).toStrictEqual([400, 'REQUEST_INVALID']);
    }
    for (let i = 0; i < 3; i += 1) await newSquad(me.token);
    const fourth = await create(me.token, { name: '第四个' });
    expect([fourth.status, fourth.type, reason(fourth)]).toStrictEqual([
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
      body: { version: 1, name: 'a' },
    });
    expect([refused.status, reason(refused)]).toStrictEqual([401, 'AUTH_TOKEN_MISSING']);
  });
});

describe('joining by invite code', () => {
  it('previews, joins, and joining again changes nothing', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const squad = await newSquad(me.token, '周末网球');
    const typed = `${squad.inviteCode.slice(0, 4).toLowerCase()}-${squad.inviteCode.slice(4)}`;

    const preview = await call({
      method: 'GET',
      path: `/squad-invites/${typed}`,
      token: friend.token,
    });
    expect([preview.status, preview.body]).toStrictEqual([
      200,
      { version: 1, name: '周末网球', memberCount: 1, full: false, joined: false },
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

describe('reading and leaving squads', () => {
  it('lists my squads, shows one only to its members, and leaving takes me out', async () => {
    const [me, friend] = [await signUp(), await signUp()];
    const mine = await newSquad(me.token, '一');
    const theirs = await newSquad(friend.token, '二');
    await call({
      method: 'POST',
      path: `/squad-invites/${theirs.inviteCode}/accept`,
      token: me.token,
    });

    const list = await call({ method: 'GET', path: '/me/squads', token: me.token });
    expect(list.status).toBe(200);
    expect(SquadListBody.parse(list.body).squads.map(({ name }) => name)).toStrictEqual([
      '一',
      '二',
    ]);

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
      ['DELETE', '/squads/not-a-uuid/members/me'],
    ] as const) {
      const malformed = await call({ method, path, token: friend.token });
      expect([malformed.status, reason(malformed)]).toStrictEqual([400, 'REQUEST_INVALID']);
    }
    expect(
      (await call({ method: 'GET', path: `/squads/${theirs.id}`, token: me.token })).status,
    ).toBe(200);

    const left = await call({
      method: 'DELETE',
      path: `/squads/${theirs.id}/members/me`,
      token: me.token,
    });
    expect([left.status, left.body]).toStrictEqual([204, undefined]);
    const leftAgain = await call({
      method: 'DELETE',
      path: `/squads/${theirs.id}/members/me`,
      token: me.token,
    });
    expect(leftAgain.status).toBe(204);
    const after = await call({ method: 'GET', path: '/me/squads', token: me.token });
    expect(SquadListBody.parse(after.body).squads.map(({ id }) => id)).toStrictEqual([mine.id]);
    const gone = await call({ method: 'GET', path: `/squads/${theirs.id}`, token: me.token });
    expect(reason(gone)).toBe('SQUAD_NOT_JOINED');
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

  it('shows anyone the name, size and whether it is full, and nothing about who is in it', async () => {
    const creator = await signUp();
    const squad = await newSquad(creator.token, '周末网球');
    const typed = `${squad.inviteCode.slice(0, 4).toLowerCase()}-${squad.inviteCode.slice(4)}`;
    expect(await lookUp(typed, '203.0.113.10')).toStrictEqual({
      status: 200,
      cacheControl: 'no-store',
      retryAfter: null,
      body: { version: 1, name: '周末网球', memberCount: 1, full: false },
    });
  });

  it('answers an unknown code and one that can’t be a code alike', async () => {
    for (const code of ['ZZZZZZZZ', 'not-a-code!']) {
      const response = await lookUp(code, '203.0.113.11');
      expect([response.status, reason(response)]).toStrictEqual([404, 'INVITE_CODE_UNKNOWN']);
    }
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
