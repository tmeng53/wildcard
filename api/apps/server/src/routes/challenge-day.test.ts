import { SquadId, type Squads } from '@wildcard/squads';
import { TimeZone } from '@wildcard/time-zones';
import { describe, expect, it } from 'vitest';

import { challengeToday } from './challenge-day.js';

const squad = SquadId.parse('00000000-0000-4000-8000-000000000001');
const member = '00000000-0000-4000-8000-000000000002';

/** The squad on Toronto's clock, the member on `zone`, with a challenge delivered on `reached`. */
function today({
  now,
  zone,
  reached = [],
}: {
  now: string;
  zone?: string;
  reached?: readonly string[];
}) {
  const squads: Pick<Squads, 'timeZonesAt'> = {
    timeZonesAt: () => Promise.resolve(() => 'America/Toronto'),
  };
  const members = {
    findProfile: () =>
      Promise.resolve(zone === undefined ? undefined : { timeZone: TimeZone.parse(zone) }),
  };
  const coachActivity = {
    challenge: ({ today: day }: { today: string }) =>
      Promise.resolve(reached.includes(day) ? { day } : undefined),
  };
  return challengeToday({ squads, members, coachActivity }, { squad, member, now: new Date(now) });
}

describe('challengeToday', () => {
  it('keeps the squad’s day for a member with no zone saved', async () => {
    // 01:00 on the 20th in Toronto.
    expect(await today({ now: '2026-11-20T06:00:00Z' })).toBe('2026-11-20');
  });

  it('keeps a member behind the squad on their own day until their midnight', async () => {
    // 22:00 on the 19th in Vancouver, already 01:00 on the 20th in Toronto.
    expect(await today({ now: '2026-11-20T06:00:00Z', zone: 'America/Vancouver' })).toBe(
      '2026-11-19',
    );
    // 03:30 on the 20th in Vancouver: their own day started on the squad's 20th.
    expect(
      await today({
        now: '2026-11-20T11:30:00Z',
        zone: 'America/Vancouver',
        reached: ['2026-11-20'],
      }),
    ).toBe('2026-11-20');
  });

  it('moves a member ahead of the squad on once the squad’s today reached them', async () => {
    // 20:00 on the 20th in Shanghai, 07:00 on the 20th in Toronto: their day started on the
    // squad's 19th.
    expect(await today({ now: '2026-11-20T12:00:00Z', zone: 'Asia/Shanghai' })).toBe('2026-11-19');
    // The note of the squad's 20th, written at its 6am, reached them at once.
    expect(
      await today({ now: '2026-11-20T12:00:00Z', zone: 'Asia/Shanghai', reached: ['2026-11-20'] }),
    ).toBe('2026-11-20');
    // 08:00 on the 21st in Shanghai, still the 20th in Toronto: the 20th's stays theirs.
    expect(
      await today({ now: '2026-11-21T00:00:00Z', zone: 'Asia/Shanghai', reached: ['2026-11-20'] }),
    ).toBe('2026-11-20');
  });
});
