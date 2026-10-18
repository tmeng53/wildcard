import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresCheckInStore,
  type CheckInTables,
} from '../adapters/postgres-check-in-store.js';
import { CheckInDraft, CheckInId, MemberId, SquadId } from '../domain/check-in.js';
import { createCheckIns } from './check-ins.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<CheckInTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

const now = new Date('2026-10-18T20:00:00.000Z');
const checkIns = createCheckIns({ store: createPostgresCheckInStore(db), clock: () => now });

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

async function newSquad(...members: MemberId[]) {
  const id = SquadId.parse(randomUUID());
  await sql`insert into public.squads (id, name) values (${id}, 'squad')`.execute(db);
  for (const member of members) {
    await sql`insert into public.squad_members (squad_id, member_id) values (${id}, ${member})`.execute(
      db,
    );
  }
  return id;
}

/** A check-in for the 18th; a 练了 run unless `body` names another kind. */
function draft(body: { readonly audience: readonly string[] } & Record<string, unknown>) {
  return CheckInDraft.parse({
    version: 1,
    day: '2026-10-18',
    createdAt: '2026-10-18T19:30:00.000Z',
    ...('kind' in body ? {} : { kind: 'trained', training: { sport: 'run', minutes: 30 } }),
    ...body,
  });
}

const disclaimer = (text: string) => ({ kind: 'disclaimer', disclaimer: { text } });

async function savedRows(id: CheckInId) {
  return sql<{ kind: string; payload: unknown; squads: string[] }>`
    select kind, payload,
      array(select squad_id::text from check_in_squads where check_in_id = c.id order by position) as squads
    from check_ins c where id = ${id}`
    .execute(db)
    .then((result) => result.rows);
}

describe('saving a check-in', () => {
  it('stores it with its payload version and audience in order', async () => {
    const member = await newMember();
    const [a, b] = [await newSquad(member), await newSquad(member)];
    const id = CheckInId.parse(randomUUID());
    const saved = await checkIns.save({ id, member, draft: draft({ audience: [b, a] }) });
    expect(saved.created).toBe(true);
    expect(await savedRows(id)).toStrictEqual([
      { kind: 'trained', payload: { version: 1, sport: 'run', minutes: 30 }, squads: [b, a] },
    ]);
  });

  it('treats the same check-in again as saved, even after its time window', async () => {
    const member = await newMember();
    const squad = await newSquad(member);
    const id = CheckInId.parse(randomUUID());
    const body = draft({ audience: [squad] });
    await checkIns.save({ id, member, draft: body });
    const late = createCheckIns({
      store: createPostgresCheckInStore(db),
      clock: () => new Date('2026-10-25T00:00:00.000Z'),
    });
    const retry = await late.save({
      id,
      member,
      draft: draft({ audience: [squad], createdAt: '2026-10-18T12:30:00.000-07:00' }),
    });
    expect([retry.created, retry.checkIn.createdAt.toISOString()]).toStrictEqual([
      false,
      '2026-10-18T19:30:00.000Z',
    ]);
  });

  it('refuses different contents, or another member, under a saved id', async () => {
    const member = await newMember();
    const other = await newMember();
    const squad = await newSquad(member, other);
    const id = CheckInId.parse(randomUUID());
    await checkIns.save({ id, member, draft: draft({ audience: [squad] }) });
    await expect(
      checkIns.save({
        id,
        member,
        draft: draft({ audience: [squad], training: { sport: 'run', minutes: 31 } }),
      }),
    ).rejects.toMatchObject({ reason: 'CHECK_IN_ID_CONFLICT' });
    await expect(
      checkIns.save({ id, member: other, draft: draft({ audience: [squad] }) }),
    ).rejects.toMatchObject({ reason: 'CHECK_IN_ID_CONFLICT' });
  });

  it('saves overlapping retries of one check-in once', async () => {
    const member = await newMember();
    const squad = await newSquad(member);
    const id = CheckInId.parse(randomUUID());
    const body = draft({ audience: [squad] });
    const results = await Promise.all(
      Array.from({ length: 5 }, () => checkIns.save({ id, member, draft: body })),
    );
    expect(results.map((result) => result.created).sort()).toStrictEqual([
      false,
      false,
      false,
      false,
      true,
    ]);
    expect(await savedRows(id)).toHaveLength(1);
  });

  it('recognises a retry that overlapped the first save, from the database’s answer', async () => {
    // A store that misses the first lookup, as when two saves look before either has written.
    const real = createPostgresCheckInStore(db);
    const overlapping = () => {
      let missed = false;
      return createCheckIns({
        store: {
          ...real,
          find: (id) => {
            if (missed) return real.find(id);
            missed = true;
            return Promise.resolve(undefined);
          },
        },
        clock: () => now,
      });
    };
    const member = await newMember();
    const squad = await newSquad(member);
    for (const body of [
      draft({ audience: [squad] }),
      draft({ audience: [squad], ...disclaimer('加班') }),
    ]) {
      const id = CheckInId.parse(randomUUID());
      await checkIns.save({ id, member, draft: body });
      expect((await overlapping().save({ id, member, draft: body })).created).toBe(false);
    }
    const id = CheckInId.parse(randomUUID());
    await checkIns.save({ id, member, draft: draft({ audience: [squad] }) });
    await expect(
      overlapping().save({
        id,
        member,
        draft: draft({ audience: [squad], training: { sport: 'swim', minutes: 30 } }),
      }),
    ).rejects.toMatchObject({ reason: 'CHECK_IN_ID_CONFLICT' });
  });

  it('allows one disclaimer a day, even when two are saved at once', async () => {
    const member = await newMember();
    const squad = await newSquad(member);
    const results = await Promise.allSettled(
      ['加班', '下雨'].map((text) =>
        checkIns.save({
          id: CheckInId.parse(randomUUID()),
          member,
          draft: draft({ audience: [squad], ...disclaimer(text) }),
        }),
      ),
    );
    expect(results.map((result) => result.status).sort()).toStrictEqual(['fulfilled', 'rejected']);
    expect(results.find((result) => result.status === 'rejected')).toMatchObject({
      reason: { reason: 'DISCLAIMER_ALREADY_POSTED' },
    });
    // A training on the same day, and a disclaimer the next day, are fine.
    await checkIns.save({
      id: CheckInId.parse(randomUUID()),
      member,
      draft: draft({ audience: [squad] }),
    });
    const tomorrow = await checkIns.save({
      id: CheckInId.parse(randomUUID()),
      member,
      draft: draft({ audience: [squad], day: '2026-10-19', ...disclaimer('累') }),
    });
    expect(tomorrow.created).toBe(true);
  });

  it('refuses a squad the member isn’t in, or one that doesn’t exist', async () => {
    const member = await newMember();
    const mine = await newSquad(member);
    const theirs = await newSquad(await newMember());
    for (const squad of [theirs, randomUUID()]) {
      await expect(
        checkIns.save({
          id: CheckInId.parse(randomUUID()),
          member,
          draft: draft({ audience: [mine, squad] }),
        }),
      ).rejects.toMatchObject({ reason: 'SQUAD_NOT_JOINED', squadId: squad });
    }
  });

  it('refuses a check-in outside its time window', async () => {
    const member = await newMember();
    const squad = await newSquad(member);
    const save = (createdAt: string, day: string) =>
      checkIns.save({
        id: CheckInId.parse(randomUUID()),
        member,
        draft: draft({ audience: [squad], createdAt, day }),
      });
    await expect(save('2026-10-16T19:59:59.999Z', '2026-10-16')).rejects.toMatchObject({
      reason: 'CHECK_IN_TOO_OLD',
    });
    await expect(save('2026-10-18T20:05:00.001Z', '2026-10-18')).rejects.toMatchObject({
      reason: 'CHECK_IN_IN_THE_FUTURE',
    });
    await expect(save('2026-10-18T19:00:00.000Z', '2026-10-20')).rejects.toMatchObject({
      reason: 'CHECK_IN_DAY_MISMATCH',
    });
  });
});

describe('listing check-ins', () => {
  async function save(member: MemberId, body: Parameters<typeof draft>[0]) {
    const { checkIn } = await checkIns.save({
      id: CheckInId.parse(randomUUID()),
      member,
      draft: draft(body),
    });
    return checkIn.id;
  }

  it('shows a squad’s check-ins from members still in it, newest first', async () => {
    const [me, friend, leaver] = [await newMember(), await newMember(), await newMember()];
    const squad = await newSquad(me, friend, leaver);
    const elsewhere = await newSquad(friend);
    const mine = await save(me, {
      audience: [squad],
      day: '2026-10-17',
      createdAt: '2026-10-17T15:00:00.000Z',
    });
    const theirs = await save(friend, { audience: [elsewhere, squad] });
    await save(friend, { audience: [elsewhere] });
    await save(leaver, { audience: [squad] });
    await sql`delete from squad_members where member_id = ${leaver}`.execute(db);

    const listed = await checkIns.listForSquad({
      viewer: me,
      squad,
      days: { from: '2026-10-17', to: '2026-10-18' },
    });
    expect(listed.map(({ id, audience }) => ({ id, audience }))).toStrictEqual([
      // The friend's other squad is hidden from me.
      { id: theirs, audience: [squad] },
      { id: mine, audience: [squad] },
    ]);
  });

  it('keeps to the days asked for', async () => {
    const me = await newMember();
    const squad = await newSquad(me);
    await save(me, { audience: [squad], day: '2026-10-17', createdAt: '2026-10-17T15:00:00.000Z' });
    const today = await save(me, { audience: [squad] });
    const days = { from: '2026-10-18', to: '2026-10-18' };
    expect(
      (await checkIns.listForSquad({ viewer: me, squad, days })).map(({ id }) => id),
    ).toStrictEqual([today]);
    expect((await checkIns.listMine({ member: me, days })).map(({ id }) => id)).toStrictEqual([
      today,
    ]);
  });

  it('shows a squad only to its members', async () => {
    const squad = await newSquad(await newMember());
    await expect(
      checkIns.listForSquad({
        viewer: await newMember(),
        squad,
        days: { from: '2026-10-18', to: '2026-10-18' },
      }),
    ).rejects.toMatchObject({ reason: 'SQUAD_NOT_JOINED' });
  });

  it('shows a member all their own check-ins with their whole audience', async () => {
    const me = await newMember();
    const [a, b] = [await newSquad(me), await newSquad(me)];
    const both = await save(me, { audience: [b, a], createdAt: '2026-10-18T19:00:00.000Z' });
    const later = await save(me, { audience: [a], ...disclaimer('今天休息') });
    const other = await newMember();
    await save(other, { audience: [await newSquad(other)] });
    const listed = await checkIns.listMine({
      member: me,
      days: { from: '2026-10-12', to: '2026-10-18' },
    });
    expect(listed.map(({ id, audience, kind }) => ({ id, audience, kind }))).toStrictEqual([
      { id: later, audience: [a], kind: 'disclaimer' },
      { id: both, audience: [b, a], kind: 'trained' },
    ]);
  });
});
