import { describe, expect, it } from 'vitest';

import {
  CheckInDraft,
  CheckInId,
  MemberId,
  SquadId,
  entryFromStored,
  isSameCheckIn,
  photosOf,
  recordFromDraft,
  storedPayload,
} from './check-in.js';
import { PhotoPath } from './photos.js';

const squad = '6f1c1d2e-3b4a-4c5d-8e9f-0a1b2c3d4e5f';
const otherSquad = '7a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

const base = {
  version: 1,
  day: '2026-10-18',
  createdAt: '2026-10-18T14:03:00.123Z',
  audience: [squad],
};
const trained = { ...base, kind: 'trained', training: { sport: 'run' } };

/** The paths of the issues a draft fails with, or 'ok'. */
function issues(body: unknown) {
  const result = CheckInDraft.safeParse(body);
  return result.success ? 'ok' : result.error.issues.map((issue) => issue.path.join('.'));
}

describe('CheckInDraft', () => {
  it('reads each kind with its own fields', () => {
    expect(
      [
        trained,
        { ...base, kind: 'healthyMeal', meal: { caption: '沙拉' } },
        { ...base, kind: 'cheatMeal', meal: {} },
        { ...base, kind: 'disclaimer', disclaimer: { text: '加班到十点' } },
        {
          ...base,
          kind: 'trained',
          training: { sport: 'custom', customSport: '飞盘', caption: '爽' },
        },
      ].map(issues),
    ).toStrictEqual(['ok', 'ok', 'ok', 'ok', 'ok']);
  });

  it('keeps the moment to the millisecond, whatever the offset', () => {
    const parse = (createdAt: string) =>
      CheckInDraft.parse({ ...trained, createdAt }).createdAt.toISOString();
    expect(parse('2026-10-18T07:03:00.123456-07:00')).toBe('2026-10-18T14:03:00.123Z');
    expect(parse('2026-10-18T14:03:00Z')).toBe('2026-10-18T14:03:00.000Z');
  });

  it('refuses fields that don’t match the kind', () => {
    expect(issues({ ...base, kind: 'trained', meal: {} })).toStrictEqual(['training', '']);
    expect(issues({ ...trained, meal: {} })).toStrictEqual(['']);
    expect(issues({ ...base, kind: 'napped', disclaimer: { text: '困' } })).toStrictEqual(['kind']);
  });

  it('refuses unknown fields: no calories', () => {
    expect(issues({ ...trained, training: { ...trained.training, calories: 300 } })).toStrictEqual([
      'training',
    ]);
    expect(
      issues({ ...base, kind: 'disclaimer', disclaimer: { text: '困', caption: '真的' } }),
    ).toStrictEqual(['disclaimer']);
  });

  it('refuses a missing or null field instead of letting it through', () => {
    expect(issues({ ...trained, training: {} })).toStrictEqual(['training.sport']);
    expect(issues({ ...trained, training: { sport: null } })).toStrictEqual(['training.sport']);
    expect(issues({ ...trained, training: { sport: 'custom', customSport: null } })).toStrictEqual([
      'training.customSport',
    ]);
    expect(issues({ ...trained, day: null })).toStrictEqual(['day']);
    expect(
      issues({
        version: 1,
        day: '2026-10-18',
        createdAt: base.createdAt,
        kind: 'trained',
        training: { sport: 'run' },
      }),
    ).toStrictEqual(['audience']);
  });

  it('refuses minutes and meal types, which v1 doesn’t have', () => {
    expect(issues({ ...trained, training: { sport: 'run', minutes: 30 } })).toStrictEqual([
      'training',
    ]);
    expect(issues({ ...base, kind: 'healthyMeal', meal: { slot: 'lunch' } })).toStrictEqual([
      'meal',
    ]);
  });

  it('takes a listed sport without a name, or custom with one', () => {
    const training = (fields: object) => issues({ ...trained, training: { ...fields } });
    expect(training({ sport: 'pickleball' })).toBe('ok');
    expect(training({ sport: 'quidditch' })).toStrictEqual(['training.sport']);
    expect(training({ sport: 'custom' })).toStrictEqual(['training.customSport']);
    expect(training({ sport: 'run', customSport: '慢跑' })).toStrictEqual(['training.customSport']);
    expect(training({ sport: 'custom', customSport: '   ' })).toStrictEqual([
      'training.customSport',
    ]);
  });

  it('takes 1 to 3 different squads', () => {
    const audience = (squads: unknown) => issues({ ...trained, audience: squads });
    expect(audience([squad, otherSquad])).toBe('ok');
    expect(audience([])).toStrictEqual(['audience']);
    expect(audience([squad, squad])).toStrictEqual(['audience']);
    expect(audience(['not-a-uuid'])).toStrictEqual(['audience.0']);
    expect(
      audience([
        squad,
        otherSquad,
        '8b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e',
        '9c4d5e6f-7a8b-4c9d-8e1f-2a3b4c5d6e7f',
      ]),
    ).toStrictEqual(['audience']);
  });

  it('refuses another version, a bad day and a moment without a zone', () => {
    expect(issues({ ...trained, version: 2 })).toStrictEqual(['version']);
    expect(issues({ ...trained, day: '2026-02-30' })).toStrictEqual(['day']);
    expect(issues({ ...trained, createdAt: '2026-10-18T14:03:00' })).toStrictEqual(['createdAt']);
  });

  it('refuses a disclaimer longer than 40 characters', () => {
    expect(
      issues({ ...base, kind: 'disclaimer', disclaimer: { text: '累'.repeat(41) } }),
    ).toStrictEqual(['disclaimer.text']);
  });
});

describe('photos on a check-in', () => {
  const photo = (id: string) => ({ path: `${squad}/${id}` });
  const cover = photo('1d2e3f4a-5b6c-4d7e-8f9a-0b1c2d3e4f5a');
  const second = photo('2e3f4a5b-6c7d-4e8f-9a0b-1c2d3e4f5a6b');

  it('takes 1 to 3 on any kind, the cover first', () => {
    expect(issues({ ...trained, training: { sport: 'run', photos: [cover, second] } })).toBe('ok');
    expect(issues({ ...base, kind: 'cheatMeal', meal: { photos: [cover] } })).toBe('ok');
    expect(
      photosOf(
        CheckInDraft.parse({
          ...base,
          kind: 'disclaimer',
          disclaimer: { text: '困', photos: [second, cover] },
        }),
      ),
    ).toStrictEqual([second, cover]);
    expect(
      photosOf(
        CheckInDraft.parse({ ...base, kind: 'healthyMeal', meal: { photos: [second, cover] } }),
      ),
    ).toStrictEqual([second, cover]);
  });

  it('refuses none listed, a repeat, or more than 3', () => {
    expect(issues({ ...trained, training: { sport: 'run', photos: [] } })).toStrictEqual([
      'training.photos',
    ]);
    expect(
      issues({ ...trained, training: { sport: 'run', photos: [cover, cover] } }),
    ).toStrictEqual(['training.photos']);
    expect(
      issues({
        ...base,
        kind: 'disclaimer',
        disclaimer: { text: '困', photos: [cover, second, photo(squad), photo(otherSquad)] },
      }),
    ).toStrictEqual(['disclaimer.photos']);
  });
});

describe('a saved check-in', () => {
  const ids = {
    id: CheckInId.parse('1d2e3f4a-5b6c-4d7e-8f9a-0b1c2d3e4f5a'),
    member: MemberId.parse('2e3f4a5b-6c7d-4e8f-9a0b-1c2d3e4f5a6b'),
  };
  const record = recordFromDraft(CheckInDraft.parse(trained), ids);

  it('stores its fields with their version, and reads them back', () => {
    expect(storedPayload(record)).toStrictEqual({ version: 1, sport: 'run' });
    expect(
      entryFromStored({ kind: 'trained', payload: storedPayload(record), photos: [] }),
    ).toStrictEqual({ kind: 'trained', training: { sport: 'run' } });
  });

  it('keeps photos out of the stored fields, and reads them back from their rows', () => {
    const photos = [
      { path: PhotoPath.parse(`${ids.member}/3f4a5b6c-7d8e-4f9a-8b1c-2d3e4f5a6b7c`) },
    ];
    const meal = recordFromDraft(
      CheckInDraft.parse({ ...base, kind: 'healthyMeal', meal: { caption: '沙拉', photos } }),
      ids,
    );
    expect(storedPayload(meal)).toStrictEqual({ version: 1, caption: '沙拉' });
    expect(
      entryFromStored({ kind: 'healthyMeal', payload: storedPayload(meal), photos }),
    ).toStrictEqual({ kind: 'healthyMeal', meal: { caption: '沙拉', photos } });
    const disclaimer = recordFromDraft(
      CheckInDraft.parse({ ...base, kind: 'disclaimer', disclaimer: { text: '困', photos } }),
      ids,
    );
    expect(storedPayload(disclaimer)).toStrictEqual({ version: 1, text: '困' });
    expect(
      entryFromStored({ kind: 'disclaimer', payload: storedPayload(disclaimer), photos }),
    ).toStrictEqual({ kind: 'disclaimer', disclaimer: { text: '困', photos } });
  });

  it('refuses stored fields that break the shape', () => {
    expect(() =>
      entryFromStored({ kind: 'trained', payload: { version: 2, sport: 'run' }, photos: [] }),
    ).toThrow('version');
    expect(() =>
      entryFromStored({ kind: 'trained', payload: { version: 1, sport: 'skydiving' }, photos: [] }),
    ).toThrow('sport');
  });

  it('is the same check-in only with the same contents', () => {
    const again = (body: object) => recordFromDraft(CheckInDraft.parse(body), ids);
    expect(isSameCheckIn(record, again(trained))).toBe(true);
    expect(
      isSameCheckIn(record, again({ ...trained, createdAt: '2026-10-18T14:03:00.123+00:00' })),
    ).toBe(true);
    expect(
      isSameCheckIn(record, again({ ...trained, createdAt: '2026-10-18T14:03:00.124Z' })),
    ).toBe(false);
    expect(isSameCheckIn(record, again({ ...trained, training: { sport: 'swim' } }))).toBe(false);
    expect(isSameCheckIn(record, again({ ...trained, audience: [squad, otherSquad] }))).toBe(false);
    expect(
      isSameCheckIn(
        recordFromDraft(CheckInDraft.parse({ ...trained, audience: [squad, otherSquad] }), ids),
        again({ ...trained, audience: [otherSquad, squad] }),
      ),
    ).toBe(false);
    expect(
      isSameCheckIn(record, {
        ...record,
        member: MemberId.parse('3f4a5b6c-7d8e-4f9a-8b1c-2d3e4f5a6b7c'),
      }),
    ).toBe(false);
    expect(isSameCheckIn(record, { ...record, audience: [SquadId.parse(otherSquad)] })).toBe(false);
  });
});
