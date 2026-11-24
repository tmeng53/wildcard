import { SquadId, type Squads } from '@wildcard/squads';
import { TimeZone } from '@wildcard/time-zones';
import { describe, expect, it } from 'vitest';

import { challengeToday } from './challenge-day.js';

const squad = SquadId.parse('00000000-0000-4000-8000-000000000001');
const member = '00000000-0000-4000-8000-000000000002';

/** Today for a member on `zone` (none saved when left out) in a squad on `squadZone`'s clock. */
function today({ now, zone, squadZone }: { now: string; zone?: string; squadZone: string }) {
  const squads: Pick<Squads, 'timeZonesAt'> = {
    timeZonesAt: () => Promise.resolve(() => squadZone),
  };
  const members = {
    findProfile: () =>
      Promise.resolve(zone === undefined ? undefined : { timeZone: TimeZone.parse(zone) }),
  };
  return challengeToday({ squads, members }, { squad, member, now: new Date(now) });
}

describe('challengeToday', () => {
  it('keeps the squad’s day for a member with no zone saved', async () => {
    // 01:00 on the 20th in Toronto.
    expect(await today({ now: '2026-11-20T06:00:00Z', squadZone: 'America/Toronto' })).toBe(
      '2026-11-20',
    );
  });

  it('keeps a member behind the squad on their own day until their midnight', async () => {
    const toronto = { squadZone: 'America/Toronto', zone: 'America/Vancouver' };
    // 22:00 on the 19th in Vancouver, already 01:00 on the 20th in Toronto.
    expect(await today({ now: '2026-11-20T06:00:00Z', ...toronto })).toBe('2026-11-19');
    // 00:30 on the 20th in Vancouver.
    expect(await today({ now: '2026-11-20T08:30:00Z', ...toronto })).toBe('2026-11-20');
    // 17:00 on the 19th in New York, 06:00 on the 20th in Shanghai: the squad's 20th note has
    // reached them, but the 19th's stays theirs until their own midnight.
    expect(
      await today({
        now: '2026-11-19T22:00:00Z',
        squadZone: 'Asia/Shanghai',
        zone: 'America/New_York',
      }),
    ).toBe('2026-11-19');
  });

  it('keeps a member ahead of the squad on the squad’s day until the squad’s midnight', async () => {
    const toronto = { squadZone: 'America/Toronto', zone: 'Asia/Shanghai' };
    // 20:00 on the 20th in Shanghai, 07:00 on the 20th in Toronto: the 20th's note reached them.
    expect(await today({ now: '2026-11-20T12:00:00Z', ...toronto })).toBe('2026-11-20');
    // 08:00 on the 21st in Shanghai, still 19:00 on the 20th in Toronto.
    expect(await today({ now: '2026-11-21T00:00:00Z', ...toronto })).toBe('2026-11-20');
    // 13:30 on the 21st in Shanghai, 00:30 on the 21st in Toronto.
    expect(await today({ now: '2026-11-21T05:30:00Z', ...toronto })).toBe('2026-11-21');
  });
});
