import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresSquadPlaceStore,
  type SquadPlaceTables,
} from '../adapters/postgres-squad-place-store.js';
import { MemberId } from '../domain/place-rating.js';
import { SquadId, SquadPlaceId } from '../domain/squad-place.js';
import { SquadNotJoinedError, SquadPlaceIdConflictError } from '../errors.js';
import { createSquadPlaces } from './squad-places.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<SquadPlaceTables>({
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

/** A squad row (for its key); who is in it is kept here, as the squads module would answer. */
async function newSquad() {
  const id = SquadId.parse(randomUUID());
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'squad', ${id})`.execute(
    db,
  );
  return id;
}

describe('a squad’s own places', () => {
  it('adds a place once for the squad, lists it to members, and refuses others', async () => {
    const [me, friend, outsider] = [await newMember(), await newMember(), await newMember()];
    const [squad, other] = [await newSquad(), await newSquad()];
    const rosters = new Map([
      [me, new Set([squad])],
      [friend, new Set([squad])],
      [outsider, new Set([other])],
    ]);
    let now = new Date('2026-11-12T20:00:00Z');
    const places = createSquadPlaces({
      store: createPostgresSquadPlaceStore(db),
      membership: { squadIdsOf: (member) => Promise.resolve(rosters.get(member) ?? new Set()) },
      clock: () => now,
    });
    const id = SquadPlaceId.parse(randomUUID());
    const fields = {
      id,
      squad,
      name: '小区健身角',
      kind: 'gym',
      latitude: 40.7,
      longitude: -73.9,
    } as const;
    const added = await places.add({ ...fields, member: me });
    expect(added.created).toBe(true);
    now = new Date('2026-11-12T21:00:00Z');
    // A retry gives back the place as it was first added.
    expect(await places.add({ ...fields, member: me })).toStrictEqual({
      place: { ...added.place },
      created: false,
    });
    await expect(places.add({ ...fields, name: '另一个', member: me })).rejects.toBeInstanceOf(
      SquadPlaceIdConflictError,
    );
    await expect(places.add({ ...fields, member: outsider })).rejects.toBeInstanceOf(
      SquadNotJoinedError,
    );
    expect(await places.list({ squad, viewer: friend })).toStrictEqual([
      {
        id,
        squad,
        addedBy: me,
        name: '小区健身角',
        kind: 'gym',
        latitude: 40.7,
        longitude: -73.9,
        addedAt: new Date('2026-11-12T20:00:00Z'),
      },
    ]);
    await expect(places.list({ squad, viewer: outsider })).rejects.toBeInstanceOf(
      SquadNotJoinedError,
    );

    await expect(
      db.updateTable('squad_places').set({ name: '改名' }).where('id', '=', id).execute(),
    ).rejects.toThrow();
    // The adder's account going keeps the place for the squad.
    await sql`delete from auth.users where id = ${me}`.execute(db);
    const [kept] = await places.list({ squad, viewer: friend });
    expect(kept?.addedBy).toBeUndefined();
  });
});
