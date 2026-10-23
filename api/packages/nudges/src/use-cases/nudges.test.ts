import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresNudgeStore, type NudgeTables } from '../adapters/postgres-nudge-store.js';
import { MemberId, SquadId } from '../domain/nudge.js';
import { NotASquadmateError, OwnNudgeError, SquadNotJoinedError } from '../errors.js';
import type { SquadMembership } from '../ports.js';
import { createNudges } from './nudges.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<NudgeTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

/** A squad in the database (for its key), with who is in it now kept here. */
async function squadOf(rosters: Map<SquadId, MemberId[]>, members: MemberId[]) {
  const id = SquadId.parse(randomUUID());
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'Squad', ${id})`.execute(
    db,
  );
  rosters.set(id, members);
  return id;
}

function membershipOf(rosters: Map<SquadId, MemberId[]>): SquadMembership {
  return {
    squadIdsOf: (member) =>
      Promise.resolve(
        new Set([...rosters].filter(([, members]) => members.includes(member)).map(([s]) => s)),
      ),
    membersOf: (squad) => Promise.resolve([...(rosters.get(squad) ?? [])]),
  };
}

function nudgesAt(
  rosters: Map<SquadId, MemberId[]>,
  { start, zones = new Map() }: { start: string; zones?: ReadonlyMap<MemberId, string> },
) {
  let now = new Date(start);
  const nudges = createNudges({
    store: createPostgresNudgeStore(db),
    membership: membershipOf(rosters),
    timeZoneOf: (member) => Promise.resolve(zones.get(member)),
    clock: () => now,
  });
  return {
    nudges,
    at: (time: string) => {
      now = new Date(time);
    },
  };
}

const rowsTo = (member: MemberId) =>
  db
    .selectFrom('nudges')
    .select(['from_member_id', 'kind', sql<string>`day::text`.as('day')])
    .where('to_member_id', '=', member)
    .orderBy('id')
    .execute();

describe('sending a nudge', () => {
  it('saves one poke a day from one member to another', async () => {
    const rosters = new Map<SquadId, MemberId[]>();
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await squadOf(rosters, [ann, bo]);
    const { nudges, at } = nudgesAt(rosters, { start: '2026-10-23T14:00:00.000Z' });
    expect(await nudges.send({ from: ann, to: bo, squad, kind: 'poke' })).toBe('created');
    expect(await nudges.send({ from: ann, to: bo, squad, kind: 'poke' })).toBe('unchanged');
    expect(await nudges.send({ from: bo, to: ann, squad, kind: 'poke' })).toBe('created');
    at('2026-10-24T14:00:00.000Z');
    expect(await nudges.send({ from: ann, to: bo, squad, kind: 'poke' })).toBe('created');
    expect(await rowsTo(bo)).toStrictEqual([
      { from_member_id: ann, kind: 'poke', day: '2026-10-23' },
      { from_member_id: ann, kind: 'poke', day: '2026-10-24' },
    ]);
  });

  it('keeps one when the same nudge is sent several times at once', async () => {
    const rosters = new Map<SquadId, MemberId[]>();
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await squadOf(rosters, [ann, bo]);
    const { nudges } = nudgesAt(rosters, { start: '2026-10-23T14:00:00.000Z' });
    const sent = await Promise.all(
      [1, 2, 3].map(() => nudges.send({ from: ann, to: bo, squad, kind: 'poke' })),
    );
    expect(sent.filter((outcome) => outcome === 'created')).toHaveLength(1);
    expect(await rowsTo(bo)).toHaveLength(1);
  });

  it('counts the day on the sender’s clock', async () => {
    const rosters = new Map<SquadId, MemberId[]>();
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await squadOf(rosters, [ann, bo]);
    // 11pm on the 22nd in Los Angeles, already the 23rd in UTC.
    const { nudges, at } = nudgesAt(rosters, {
      start: '2026-10-23T06:00:00.000Z',
      zones: new Map([[ann, 'America/Los_Angeles']]),
    });
    await nudges.send({ from: ann, to: bo, squad, kind: 'poke' });
    at('2026-10-23T08:00:00.000Z');
    await nudges.send({ from: ann, to: bo, squad, kind: 'poke' });
    expect((await rowsTo(bo)).map(({ day }) => day)).toStrictEqual(['2026-10-22', '2026-10-23']);
  });

  it('refuses oneself, a squad the sender isn’t in and someone outside it', async () => {
    const rosters = new Map<SquadId, MemberId[]>();
    const [ann, bo, cy] = [await newMember(), await newMember(), await newMember()];
    const squad = await squadOf(rosters, [ann, bo]);
    const { nudges } = nudgesAt(rosters, { start: '2026-10-23T14:00:00.000Z' });
    await expect(nudges.send({ from: ann, to: ann, squad, kind: 'poke' })).rejects.toThrow(
      OwnNudgeError,
    );
    await expect(nudges.send({ from: cy, to: bo, squad, kind: 'poke' })).rejects.toThrow(
      SquadNotJoinedError,
    );
    await expect(nudges.send({ from: ann, to: cy, squad, kind: 'poke' })).rejects.toThrow(
      NotASquadmateError,
    );
    expect(await rowsTo(bo)).toStrictEqual([]);
    expect(await rowsTo(cy)).toStrictEqual([]);
  });

  it('never changes a nudge once sent, but an account’s deletion takes it', async () => {
    const rosters = new Map<SquadId, MemberId[]>();
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await squadOf(rosters, [ann, bo]);
    const { nudges } = nudgesAt(rosters, { start: '2026-10-23T14:00:00.000Z' });
    await nudges.send({ from: ann, to: bo, squad, kind: 'poke' });
    await expect(
      sql`update public.nudges set day = day + 1 where to_member_id = ${bo}`.execute(db),
    ).rejects.toThrow(/append-only/);
    await expect(
      sql`delete from public.nudges where to_member_id = ${bo}`.execute(db),
    ).rejects.toThrow(/append-only/);
    await sql`delete from auth.users where id = ${ann}`.execute(db);
    expect(await rowsTo(bo)).toStrictEqual([]);
  });
});

describe('nudges received', () => {
  it('names each sender once per kind, from squadmates still in the squad', async () => {
    const rosters = new Map<SquadId, MemberId[]>();
    const [ann, bo, cy, di] = [
      await newMember(),
      await newMember(),
      await newMember(),
      await newMember(),
    ];
    const squad = await squadOf(rosters, [ann, bo, cy, di]);
    const { nudges, at } = nudgesAt(rosters, { start: '2026-10-22T14:00:00.000Z' });
    await nudges.send({ from: bo, to: ann, squad, kind: 'poke' });
    at('2026-10-23T14:00:00.000Z');
    await nudges.send({ from: bo, to: ann, squad, kind: 'poke' });
    await nudges.send({ from: cy, to: ann, squad, kind: 'poke' });
    await nudges.send({ from: di, to: ann, squad, kind: 'poke' });
    // Di leaves: their nudge no longer counts.
    rosters.set(squad, [ann, bo, cy]);
    const received = await nudges.received({
      member: ann,
      since: new Date('2026-10-22T22:00:00.000Z'),
      until: new Date('2026-10-23T22:00:00.000Z'),
    });
    expect(received).toStrictEqual(new Map([['poke', new Set([bo, cy])]]));
  });

  it('is empty after the member leaves the squad they were nudged in', async () => {
    const rosters = new Map<SquadId, MemberId[]>();
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await squadOf(rosters, [ann, bo]);
    const { nudges } = nudgesAt(rosters, { start: '2026-10-23T14:00:00.000Z' });
    await nudges.send({ from: bo, to: ann, squad, kind: 'poke' });
    rosters.set(squad, [bo]);
    const received = await nudges.received({
      member: ann,
      since: new Date('2026-10-23T00:00:00.000Z'),
      until: new Date('2026-10-24T00:00:00.000Z'),
    });
    expect(received).toStrictEqual(new Map());
  });
});

describe('a member’s nudges in a squad', () => {
  it('lists whom they poked today and who poked them in the last day, each once', async () => {
    const rosters = new Map<SquadId, MemberId[]>();
    const [ann, bo, cy, di] = [
      await newMember(),
      await newMember(),
      await newMember(),
      await newMember(),
    ];
    const squad = await squadOf(rosters, [ann, bo, cy, di]);
    const other = await squadOf(rosters, [ann, bo]);
    // 8pm on the 22nd in New York: Ann's yesterday by the read, but within the last day.
    const { nudges, at } = nudgesAt(rosters, {
      start: '2026-10-23T00:00:00.000Z',
      zones: new Map([[ann, 'America/New_York']]),
    });
    await nudges.send({ from: cy, to: ann, squad, kind: 'poke' });
    await nudges.send({ from: ann, to: bo, squad, kind: 'poke' });
    // Over a day before the read: too old.
    at('2026-10-22T12:00:00.000Z');
    await nudges.send({ from: di, to: ann, squad, kind: 'poke' });
    at('2026-10-23T14:00:00.000Z');
    await nudges.send({ from: bo, to: ann, squad, kind: 'poke' });
    await nudges.send({ from: bo, to: ann, squad: other, kind: 'poke' });
    await nudges.send({ from: ann, to: cy, squad, kind: 'poke' });
    await nudges.send({ from: ann, to: bo, squad: other, kind: 'poke' });
    at('2026-10-23T16:00:00.000Z');
    expect(await nudges.inSquad({ member: ann, squad, kind: 'poke' })).toStrictEqual({
      sent: [cy],
      received: [
        { from: cy, at: new Date('2026-10-23T00:00:00.000Z') },
        { from: bo, at: new Date('2026-10-23T14:00:00.000Z') },
      ],
    });
  });

  it('leaves out someone who left, and refuses a squad the member isn’t in', async () => {
    const rosters = new Map<SquadId, MemberId[]>();
    const [ann, bo, cy] = [await newMember(), await newMember(), await newMember()];
    const squad = await squadOf(rosters, [ann, bo]);
    const { nudges } = nudgesAt(rosters, { start: '2026-10-23T14:00:00.000Z' });
    await nudges.send({ from: bo, to: ann, squad, kind: 'poke' });
    await nudges.send({ from: ann, to: bo, squad, kind: 'poke' });
    rosters.set(squad, [ann]);
    expect(await nudges.inSquad({ member: ann, squad, kind: 'poke' })).toStrictEqual({
      sent: [],
      received: [],
    });
    await expect(nudges.inSquad({ member: cy, squad, kind: 'poke' })).rejects.toThrow(
      SquadNotJoinedError,
    );
  });
});
