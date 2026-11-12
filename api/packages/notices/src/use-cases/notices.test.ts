import { randomInt, randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresBroadcastStore } from '../adapters/postgres-broadcast-store.js';
import { createPostgresNoticeStore, type NoticeTables } from '../adapters/postgres-notice-store.js';
import { BroadcastId, BroadcastValue, type Broadcast } from '../domain/broadcast.js';
import { MemberId, NoticeId, SquadId, type NewNotice } from '../domain/notice.js';
import { NoticeNotFoundError } from '../errors.js';
import { createNotices } from './notices.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<NoticeTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

// Broadcasts are every member's, so the tests below that don't send one read at a time none runs.
const notices = createNotices({
  store: createPostgresNoticeStore(db),
  broadcasts: createPostgresBroadcastStore(db),
  clock: () => new Date('2000-01-01T00:00:00Z'),
});

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

async function newSquad() {
  const id = SquadId.parse(randomUUID());
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'Squad', ${id})`.execute(
    db,
  );
  return id;
}

function scene(member: MemberId, { squad, name }: { squad: SquadId; name: string }): NewNotice {
  return { member, squad, kind: 'sceneMoved', subject: { version: 1, scene: name, by: null } };
}

describe('notices', () => {
  it('tells a member of a comment once, however often it is told', async () => {
    const [me, other] = [await newMember(), await newMember()];
    const [checkIn, comment] = [randomUUID(), randomUUID()];
    const told = (member: MemberId): NewNotice => ({
      member,
      kind: 'comment',
      subject: {
        version: 1,
        alert: { key: 'push.comment', args: ['安安', '加油'] },
        checkIn,
        comment,
      },
    });

    expect(await notices.tell([told(me)])).toEqual([me]);
    expect(await notices.tell([told(me), told(other)])).toEqual([other]);

    const page = await notices.page({ member: me, limit: 10 });
    expect(page.notices.filter(({ kind }) => kind === 'comment')).toHaveLength(1);
  });

  it('pages a member’s notices newest first, and only theirs', async () => {
    const [me, other, squad] = [await newMember(), await newMember(), await newSquad()];
    await notices.tell([
      scene(me, { squad, name: 'gym' }),
      {
        member: me,
        kind: 'dailyProgress',
        subject: { version: 1, alert: { key: 'push.dailyProgress', args: ['2', '5'] } },
      },
      scene(other, { squad, name: 'pool' }),
      {
        member: me,
        kind: 'unlocked',
        subject: { version: 1, kind: 'prop', item: 'racket' },
      },
    ]);

    const first = await notices.page({ member: me, limit: 2 });
    expect(first.notices.map(({ kind }) => kind)).toEqual(['unlocked', 'dailyProgress']);
    expect(first.notices[0]?.subject).toEqual({ version: 1, kind: 'prop', item: 'racket' });
    expect(first.seenThrough).toBeUndefined();
    expect(first.next).toBe(first.notices[1]?.id);

    const second = await notices.page({ member: me, before: first.next, limit: 1 });
    expect(second.notices.map(({ kind, squad: about }) => [kind, about])).toEqual([
      ['sceneMoved', squad],
    ]);
    expect(second.next).toBeUndefined();
  });

  it('caps a page at 50', async () => {
    const [me, squad] = [await newMember(), await newSquad()];
    await notices.tell(
      Array.from({ length: 52 }, (_, at) => scene(me, { squad, name: `scene-${String(at)}` })),
    );
    const page = await notices.page({ member: me, limit: 500 });
    expect(page.notices).toHaveLength(50);
    expect(page.next).toBe(page.notices[49]?.id);
  });

  it('skips a kind this build doesn’t know, and still reaches the notices before it', async () => {
    const [me, squad] = [await newMember(), await newSquad()];
    await notices.tell([scene(me, { squad, name: 'oldest' }), scene(me, { squad, name: 'older' })]);
    await sql`insert into public.notices (member_id, kind, subject) values (${me}, 'future', '{"version":1}'), (${me}, 'future', '{"version":1}')`.execute(
      db,
    );
    await notices.tell([scene(me, { squad, name: 'newest' })]);

    const scenes = (page: Awaited<ReturnType<typeof notices.page>>) =>
      page.notices.map((notice) => (notice.kind === 'sceneMoved' ? notice.subject.scene : ''));
    const first = await notices.page({ member: me, limit: 2 });
    expect(scenes(first)).toEqual(['newest']);
    // The page ended on a skipped row: its `next` still leads on.
    const second = await notices.page({ member: me, before: first.next, limit: 1 });
    expect(scenes(second)).toEqual([]);
    const third = await notices.page({ member: me, before: second.next, limit: 2 });
    expect(scenes(third)).toEqual(['older', 'oldest']);
    expect(third.next).toBeUndefined();
  });

  it('marks seen only forward, and only the member’s own notices', async () => {
    const [me, other, squad] = [await newMember(), await newMember(), await newSquad()];
    await notices.tell([
      scene(me, { squad, name: 'gym' }),
      scene(me, { squad, name: 'pool' }),
      scene(other, { squad, name: 'park' }),
    ]);
    const [newest, older] = (await notices.page({ member: me, limit: 10 })).notices;
    const [others] = (await notices.page({ member: other, limit: 10 })).notices;
    if (newest === undefined || older === undefined || others === undefined) {
      throw new Error('notices missing');
    }

    expect(await notices.markSeen(me, older.id)).toBe('moved');
    expect(await notices.markSeen(me, newest.id)).toBe('moved');
    expect(await notices.markSeen(me, newest.id)).toBe('unchanged');
    expect(await notices.markSeen(me, older.id)).toBe('unchanged');
    expect((await notices.page({ member: me, limit: 10 })).seenThrough).toBe(newest.id);
    await expect(notices.markSeen(me, others.id)).rejects.toBeInstanceOf(NoticeNotFoundError);
    await expect(notices.markSeen(me, NoticeId.parse(2 ** 31))).rejects.toBeInstanceOf(
      NoticeNotFoundError,
    );
    const reads = await sql<{
      count: string;
    }>`select count(*) from public.notice_reads where member_id = ${me}`.execute(db);
    expect(reads.rows[0]?.count).toBe('2');
  });
});

describe('broadcasts', () => {
  // Far from now, so a test elsewhere reading notices today is never told these.
  const words = (zhHans: string) => ({ zhHans, en: `${zhHans} (en)`, zhHant: `${zhHans}（繁）` });
  // A year of this run's own, so broadcasts other runs left in the database never run with these.
  const year = String(2100 + randomInt(7800));
  const when = (iso: string) => iso.replace(/^2090/, year);
  const value = (overrides: Partial<BroadcastValue> = {}): BroadcastValue => {
    const merged = {
      version: 1,
      title: words('感恩节快到了'),
      body: words('TURKEY TROT 限定上新'),
      action: {
        label: { zhHans: '去商店街', en: 'Shop now', zhHant: '去商店街' },
        destination: 'stores',
      },
      style: 'banner',
      gifts: [],
      startsAt: '2090-11-20T00:00:00Z',
      endsAt: '2090-11-24T00:00:00Z',
      ...overrides,
    };
    return BroadcastValue.parse({
      ...merged,
      startsAt: when(merged.startsAt),
      endsAt: when(merged.endsAt),
    });
  };
  const unique = (name: string) => BroadcastId.parse(`${name}-${randomUUID().slice(0, 8)}`);
  const at = (iso: string) => {
    const gifts: [MemberId, Broadcast][] = [];
    let giving = true;
    const box = createNotices({
      store: createPostgresNoticeStore(db),
      broadcasts: createPostgresBroadcastStore(db),
      clock: () => new Date(when(iso)),
      giveGifts: async (member, broadcast) => {
        await Promise.resolve();
        if (giving) gifts.push([member, broadcast]);
        return giving;
      },
    });
    return { box, gifts, failGifts: () => (giving = false), giveAgain: () => (giving = true) };
  };

  it('takes a letter from the team with each present once', () => {
    const lines = words('谢谢你');
    const present = { kind: 'badge', id: 'idea-king' } as const;
    expect(value({ letter: { lines, presents: [present] } }).letter?.presents).toEqual([present]);
    expect(() =>
      value({ letter: { lines, presents: [present, { kind: 'badge', id: 'idea-king' }] } }),
    ).toThrow(/each present once/);
  });

  it('tells each member a running broadcast once, on their newest page, with its words now', async () => {
    const [me, admin] = [await newMember(), await newMember()];
    const id = unique('soon');
    const { box } = at('2090-11-21T12:00:00Z');
    await box.put({ id, value: value(), by: admin });

    // An older page tells nobody anything.
    expect((await box.page({ member: me, before: NoticeId.parse(1), limit: 5 })).notices).toEqual(
      [],
    );
    const first = await box.page({ member: me, limit: 5 });
    // Other tests' broadcasts may run then too.
    const told = first.notices.filter((notice) =>
      notice.kind === 'broadcast' ? notice.subject.broadcast === id : false,
    );
    expect(told.map((notice) => notice.subject)).toEqual([{ version: 1, broadcast: id }]);
    expect(first.broadcasts.get(id)?.value.title.zhHans).toBe('感恩节快到了');
    expect(first.broadcasts.get(id)?.by).toBe(admin);

    // Again, and from two opens at once: still once.
    await Promise.all([box.page({ member: me, limit: 5 }), box.page({ member: me, limit: 5 })]);
    const count = await sql<{
      count: string;
    }>`select count(*) from public.notices where member_id = ${me} and subject ->> 'broadcast' = ${id}`.execute(
      db,
    );
    expect(count.rows[0]?.count).toBe('1');

    // A fixed typo shows to whoever was told already.
    await box.put({ id, value: value({ title: words('感恩节就快到了') }), by: admin });
    expect((await box.page({ member: me, limit: 5 })).broadcasts.get(id)?.value.title.zhHans).toBe(
      '感恩节就快到了',
    );
  });

  it('tells nobody before it starts or after it ends, and logs only saves that change it', async () => {
    const [me, admin] = [await newMember(), await newMember()];
    const id = unique('window');
    await at('2090-11-01T00:00:00Z').box.put({ id, value: value(), by: admin });
    await at('2090-11-01T00:00:00Z').box.put({ id, value: value(), by: admin });
    const rows = await sql<{
      count: string;
    }>`select count(*) from public.broadcasts where broadcast_id = ${id}`.execute(db);
    expect(rows.rows[0]?.count).toBe('1');

    const before = await at('2090-11-19T23:59:59Z').box.page({ member: me, limit: 5 });
    const after = await at('2090-11-24T00:00:00Z').box.page({ member: me, limit: 5 });
    const told = [...before.notices, ...after.notices].filter((notice) =>
      notice.kind === 'broadcast' ? notice.subject.broadcast === id : false,
    );
    expect(told).toEqual([]);
  });

  it('tells only the members it names, and the others once it names everyone', async () => {
    const [me, other, admin] = [await newMember(), await newMember(), await newMember()];
    const id = unique('try');
    const { box } = at('2090-11-21T12:00:00Z');
    const told = async (member: MemberId) =>
      (await box.page({ member, limit: 5 })).notices.filter((notice) =>
        notice.kind === 'broadcast' ? notice.subject.broadcast === id : false,
      );
    await box.put({
      id,
      value: value({ members: [me.toUpperCase()], icon: { kind: 'store', id: 'powder' } }),
      by: admin,
    });
    expect(await told(other)).toEqual([]);
    expect(await told(me)).toHaveLength(1);
    expect((await box.page({ member: me, limit: 5 })).broadcasts.get(id)?.value.icon).toEqual({
      kind: 'store',
      id: 'powder',
    });

    await box.put({ id, value: value({ icon: { kind: 'store', id: 'powder' } }), by: admin });
    expect(await told(other)).toHaveLength(1);
  });

  it('gives its gifts before telling it, and tries again on a later open when they fail', async () => {
    const [me, admin] = [await newMember(), await newMember()];
    const id = unique('gift');
    const { box, gifts, failGifts, giveAgain } = at('2090-12-24T08:00:00Z');
    await box.put({
      id,
      value: value({
        gifts: [{ kind: 'piece', id: 'jingle-hat' }],
        style: 'celebration',
        startsAt: '2090-12-23T00:00:00Z',
        endsAt: '2090-12-26T00:00:00Z',
      }),
      by: admin,
    });
    const mine = (page: Awaited<ReturnType<typeof box.page>>) =>
      page.notices.filter((notice) =>
        notice.kind === 'broadcast' ? notice.subject.broadcast === id : false,
      );

    failGifts();
    expect(mine(await box.page({ member: me, limit: 5 }))).toEqual([]);
    giveAgain();
    expect(mine(await box.page({ member: me, limit: 5 }))).toHaveLength(1);
    const given = () =>
      gifts.filter(([, broadcast]) => broadcast.id === id).map(([member]) => member);
    expect(given()).toEqual([me]);
    // Told: never given again.
    await box.page({ member: me, limit: 5 });
    expect(given()).toEqual([me]);
  });
});
