// GET /me/events over the real database's notifications, notices and sign-in.
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import {
  MemberId,
  createNotices,
  createPostgresNoticeStore,
  createPostgresBroadcastStore,
} from '@wildcard/notices';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';

import { createPostgresLiveEvents } from '../adapters/postgres-live-events.js';
import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createLog } from '../log.js';
import { UserId, type LiveEvent } from '../ports.js';
import { config, signUp } from '../test-kit/local-supabase.js';
import { events, type StreamTiming } from './events.js';

const db = createDatabase(config.databaseUrl);
const liveEvents = createPostgresLiveEvents(config.liveEventsDatabaseUrl);
afterAll(async () => {
  await liveEvents.close();
  await db.destroy();
});
const notices = createNotices({
  store: createPostgresNoticeStore(db),
  broadcasts: createPostgresBroadcastStore(db),
  clock: () => new Date(),
});

function appWith(timing: StreamTiming) {
  return events({
    verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
    liveEvents,
    notices,
    members: createMembers({ store: createPostgresProfileStore(db) }),
    coachNames: () => Promise.resolve(new Map()),
    log: createLog(() => undefined),
    timing,
  });
}

const unlocked = (member: string, item: string) => ({
  member: MemberId.parse(member),
  kind: 'unlocked' as const,
  subject: { version: 1 as const, kind: 'store' as const, item },
});

/** Reads the stream's events as they come, one at a time. */
function reader(body: ReadableStream<Uint8Array> | null) {
  if (body === null) throw new Error('no body');
  const stream = body.getReader();
  const decoder = new TextDecoder();
  let buffered = '';
  return {
    /** The next event's lines, or `undefined` once the stream has ended. */
    async next(): Promise<string | undefined> {
      for (;;) {
        const end = buffered.indexOf('\n\n');
        if (end !== -1) {
          const event = buffered.slice(0, end);
          buffered = buffered.slice(end + 2);
          return event;
        }
        const { done, value } = await stream.read();
        if (done) return undefined;
        buffered += decoder.decode(value, { stream: true });
      }
    },
    cancel: () => stream.cancel(),
  };
}

describe('GET /me/events', () => {
  it('streams each notice told to the caller as it commits, and no one else’s', async () => {
    const [ana, bea] = await Promise.all([signUp(), signUp()]);
    const response = await appWith({ heartbeatMs: 60_000, maxAgeMs: 60_000 }).request(
      '/me/events',
      { headers: { authorization: `Bearer ${ana.token}` } },
    );
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toBe('text/event-stream');
    const stream = reader(response.body);
    expect(await stream.next()).toBe('event: ready\ndata: {"version":1}\nretry: 3000');

    await notices.tell([unlocked(bea.userId, 'lap-nine')]);
    await notices.tell([unlocked(ana.userId, 'no-look')]);
    const [told] = (await notices.page({ member: MemberId.parse(ana.userId), limit: 1 })).notices;
    if (told === undefined) throw new Error('no notice');

    expect(await stream.next()).toBe(
      `event: notice\ndata: ${JSON.stringify({
        version: 1,
        notice: {
          id: told.id,
          kind: 'unlocked',
          at: told.at.toISOString(),
          unlockKind: 'store',
          item: 'no-look',
        },
      })}\nid: ${String(told.id)}`,
    );
    await stream.cancel();
  });

  it('beats while quiet and ends by itself, so the app reconnects with a fresh token', async () => {
    const ana = await signUp();
    const response = await appWith({ heartbeatMs: 50, maxAgeMs: 400 }).request('/me/events', {
      headers: { authorization: `Bearer ${ana.token}` },
    });
    const stream = reader(response.body);
    expect(await stream.next()).toContain('event: ready');
    expect(await stream.next()).toBe(': ping');
    let rest = 0;
    while ((await stream.next()) !== undefined) rest += 1;
    expect(rest).toBeGreaterThan(0);
  });
});

describe('Postgres live events', () => {
  it('tells only committed notices, to the member’s subscribers, until stopped', async () => {
    const ana = await signUp();
    const heard: LiveEvent[] = [];
    const stop = await liveEvents.subscribe(UserId.parse(ana.userId), {
      event: (event) => heard.push(event),
      end: () => undefined,
    });
    await db
      .transaction()
      .execute(async (trx) => {
        await sql`insert into public.notices (member_id, kind, subject)
          values (${ana.userId}, 'unlocked', '{"version": 1, "kind": "store", "item": "rolled-back"}')`.execute(
          trx,
        );
        throw new Error('roll back');
      })
      .catch(() => undefined);
    await notices.tell([unlocked(ana.userId, 'kept')]);
    const [kept] = (await notices.page({ member: MemberId.parse(ana.userId), limit: 1 })).notices;
    await expect.poll(() => heard).toStrictEqual([{ kind: 'notice', id: kept?.id }]);

    stop();
    await notices.tell([unlocked(ana.userId, 'after')]);
    // A notification on the same connection after it shows the stopped one was passed by.
    await sql`select pg_notify('live_events', '{}')`.execute(db);
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(heard).toHaveLength(1);
  });

  it('ends every subscriber when it closes, and refuses new ones', async () => {
    const own = createPostgresLiveEvents(config.liveEventsDatabaseUrl);
    const ana = await signUp();
    let ended = 0;
    await own.subscribe(UserId.parse(ana.userId), {
      event: () => undefined,
      end: () => (ended += 1),
    });
    await own.close();
    expect(ended).toBe(1);
    await expect(
      own.subscribe(UserId.parse(ana.userId), { event: () => undefined, end: () => undefined }),
    ).rejects.toMatchObject({ reason: 'LIVE_EVENTS_UNAVAILABLE' });
  });
});
