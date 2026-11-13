import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresSavedPlaceStore,
  type SavedPlaceTables,
} from '../adapters/postgres-saved-place-store.js';
import { PlaceKey } from '@wildcard/place-ids';

import { MAX_SAVED_PLACES, MemberId } from '../domain/saved-place.js';
import { PlaceWithoutKeyError, TooManySavedPlacesError } from '../errors.js';
import { createSavedPlaces } from './saved-places.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<SavedPlaceTables>({
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

function savedPlacesAt(start: string) {
  let now = new Date(start);
  return {
    saved: createSavedPlaces({ store: createPostgresSavedPlaceStore(db), clock: () => now }),
    advance: (to: string) => {
      now = new Date(to);
    },
  };
}

const equinox = {
  name: 'Equinox Flatiron',
  appleId: 'I6FA1B2C3D4E5F6',
  category: 'fitnessCenter',
  latitude: 40.7397,
  longitude: -73.9897,
};
const park = {
  name: 'Hudson River Park',
  appleId: 'I3B4C5D6E7F8A9B0',
  latitude: 40.7277,
  longitude: -74.0112,
};
const equinoxKey = PlaceKey.parse('apple:I6FA1B2C3D4E5F6');
const parkKey = PlaceKey.parse('apple:I3B4C5D6E7F8A9B0');

async function logRows(member: MemberId) {
  const { rows } = await sql<{ kind: string; note: string | null }>`
    select kind, note from public.saved_place_events where member_id = ${member} order by id
  `.execute(db);
  return rows;
}

describe('saved places', () => {
  it('saves a place with a note, newest first, and keeps when it was saved when the note changes', async () => {
    const member = await newMember();
    const { saved, advance } = savedPlacesAt('2026-11-10T12:00:00Z');
    await saved.save({ member, place: equinox, note: '周六早上的单车课' });
    advance('2026-11-11T12:00:00Z');
    await saved.save({ member, place: park });
    advance('2026-11-12T12:00:00Z');
    const renoted = await saved.save({ member, place: equinox, note: '丸子推荐' });

    expect(renoted.savedAt).toEqual(new Date('2026-11-10T12:00:00Z'));
    expect(await saved.list(member)).toEqual([
      { key: parkKey, place: park, savedAt: new Date('2026-11-11T12:00:00Z') },
      {
        key: equinoxKey,
        place: equinox,
        note: '丸子推荐',
        savedAt: new Date('2026-11-10T12:00:00Z'),
      },
    ]);
  });

  it('logs nothing for a save that changes nothing, and clears a note left out', async () => {
    const member = await newMember();
    const { saved } = savedPlacesAt('2026-11-10T12:00:00Z');
    await saved.save({ member, place: equinox, note: '单车课' });
    await saved.save({ member, place: equinox, note: '单车课' });
    await saved.save({ member, place: equinox });

    expect(await logRows(member)).toEqual([
      { kind: 'saved', note: '单车课' },
      { kind: 'saved', note: null },
    ]);
    expect((await saved.list(member))[0]?.note).toBeUndefined();
  });

  it('removes a place, and a later save counts from then', async () => {
    const member = await newMember();
    const { saved, advance } = savedPlacesAt('2026-11-01T12:00:00Z');
    await saved.save({ member, place: equinox });
    await saved.remove({ member, key: equinoxKey });
    await saved.remove({ member, key: equinoxKey });
    expect(await saved.list(member)).toEqual([]);

    advance('2026-11-05T12:00:00Z');
    await saved.save({ member, place: equinox });
    expect((await saved.list(member))[0]?.savedAt).toEqual(new Date('2026-11-05T12:00:00Z'));
    expect((await logRows(member)).map(({ kind }) => kind)).toEqual(['saved', 'removed', 'saved']);
  });

  it('keeps each member’s places to themselves', async () => {
    const [me, mate] = [await newMember(), await newMember()];
    const { saved } = savedPlacesAt('2026-11-10T12:00:00Z');
    await saved.save({ member: me, place: equinox });
    expect(await saved.list(mate)).toEqual([]);
    await saved.remove({ member: mate, key: equinoxKey });
    expect(await saved.list(me)).toHaveLength(1);
  });

  it('saves only a place that can be found again: Maps’ by its id, a squad’s by its own', async () => {
    const member = await newMember();
    const { saved } = savedPlacesAt('2026-11-10T12:00:00Z');
    const unkeyed = {
      name: equinox.name,
      latitude: equinox.latitude,
      longitude: equinox.longitude,
    };
    await expect(saved.save({ member, place: unkeyed })).rejects.toThrow(PlaceWithoutKeyError);
    const renamed = await saved.save({ member, place: { ...equinox, name: 'Equinox' } });
    expect(renamed.key).toBe(equinoxKey);
    const squadPlaceId = 'B3000000-0000-4000-8000-000000000001';
    const corner = await saved.save({ member, place: { ...unkeyed, squadPlaceId } });
    expect(corner.key).toBe(`squad:${squadPlaceId.toLowerCase()}`);
  });

  it(`refuses more than ${String(MAX_SAVED_PLACES)} places, but still changes a saved one`, async () => {
    const member = await newMember();
    const { saved } = savedPlacesAt('2026-11-10T12:00:00Z');
    const many = Array.from({ length: MAX_SAVED_PLACES }, (_, index) => ({
      name: `Place ${String(index)}`,
      appleId: `I${String(index)}`,
      latitude: 40 + index / 1000,
      longitude: -74,
    }));
    await sql`
      insert into public.saved_place_events (member_id, place_key, kind, place, at)
      select ${member}, p.key, 'saved', p.place, now()
      from jsonb_to_recordset(${JSON.stringify(
        many.map((place) => ({ key: `apple:${place.appleId}`, place: { version: 1, place } })),
      )}::jsonb) as p(key text, place jsonb)
    `.execute(db);

    await expect(saved.save({ member, place: park })).rejects.toThrow(TooManySavedPlacesError);
    const first = many[0];
    if (first === undefined) throw new Error('no places');
    await saved.save({ member, place: first, note: '还想去' });
  });

  it('never changes or deletes a log row', async () => {
    const member = await newMember();
    const { saved } = savedPlacesAt('2026-11-10T12:00:00Z');
    await saved.save({ member, place: park });
    await expect(
      sql`update public.saved_place_events set note = 'x' where member_id = ${member}`.execute(db),
    ).rejects.toThrow(/append-only/);
    await expect(
      sql`delete from public.saved_place_events where member_id = ${member}`.execute(db),
    ).rejects.toThrow(/append-only/);
    await sql`delete from auth.users where id = ${member}`.execute(db);
    expect(await logRows(member)).toEqual([]);
  });
});
