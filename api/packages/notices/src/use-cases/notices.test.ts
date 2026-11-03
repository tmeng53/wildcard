import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresNoticeStore, type NoticeTables } from '../adapters/postgres-notice-store.js';
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

const notices = createNotices({ store: createPostgresNoticeStore(db) });

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

    const second = await notices.page({ member: me, before: first.next, limit: 2 });
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

  it('skips a kind this build doesn’t know', async () => {
    const me = await newMember();
    await sql`insert into public.notices (member_id, kind, subject) values (${me}, 'future', '{"version":1}')`.execute(
      db,
    );
    const page = await notices.page({ member: me, limit: 10 });
    expect(page.notices).toEqual([]);
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
