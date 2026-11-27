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

// The rule itself is `challengeDay`'s, tested in time-zones; this checks both zones reach it.
describe('challengeToday', () => {
  it('reads the squad’s zone and the member’s own', async () => {
    // 22:00 on the 19th in Vancouver, already 01:00 on the 20th in Toronto.
    const now = '2026-11-20T06:00:00Z';
    expect(await today({ now, squadZone: 'America/Toronto' })).toBe('2026-11-20');
    expect(await today({ now, squadZone: 'America/Toronto', zone: 'America/Vancouver' })).toBe(
      '2026-11-19',
    );
  });
});
