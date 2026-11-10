import { momentAt, NEW_YORK, wallClockAt } from '@wildcard/time-zones';

import type { CoachSettings, SquadId } from '../domain/settings.js';
import type { CoachTimeZones, CoachUsageStore } from '../ports.js';

/**
 * Why the squad's coach is off duty now, if it is: the squad spent its day's cap (its own day, on
 * its clock), or every squad together spent theirs (New York's day). The next day it is back.
 * Every model call a coach makes for a squad (its wakes, its letter) counts toward the same cap.
 */
export async function offDutyWhy(
  deps: {
    readonly usage: Pick<CoachUsageStore, 'spent'>;
    readonly clock: () => Date;
    readonly timeZonesAt: CoachTimeZones;
  },
  { squad, settings }: { readonly squad: SquadId; readonly settings: CoachSettings },
): Promise<string | undefined> {
  const now = deps.clock();
  const dayStart = (zone: string) => momentAt({ day: wallClockAt(now, zone).day, hour: 0, zone });
  const zone = (await deps.timeZonesAt([squad], now))(squad);
  const squadSpent = await deps.usage.spent({ squad, since: dayStart(zone) });
  if (squadSpent >= settings.squadDailyCapMicros) {
    return `off duty: the squad spent ${String(squadSpent)} of its ${String(settings.squadDailyCapMicros)} micros today`;
  }
  const allSpent = await deps.usage.spent({ since: dayStart(NEW_YORK) });
  if (allSpent >= settings.dailyCapMicros) {
    return `off duty: every squad spent ${String(allSpent)} of the ${String(settings.dailyCapMicros)} micros today`;
  }
  return undefined;
}
