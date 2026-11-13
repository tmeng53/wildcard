import { isKnownTimeZone, type TimeZone } from '@wildcard/time-zones';

import type { MemberId, SquadId } from '../../domain/squad.js';
import { weekAt, weekOfChange, zoneFor } from '../../domain/time-zone.js';
import { weekAfter } from '../../domain/weekly-goal.js';
import { NotSquadCaptainError, SquadTimeZoneUnknownError } from '../../errors.js';
import type { SquadStore } from '../../ports.js';
import { findSquad } from './find-squad.js';

/** A squad's time zone (小队时区), as its members see it. */
export interface SquadTimeZone {
  /** This week's zone. */
  readonly timeZone: TimeZone;
  /** Next week's: another only when a captain's change waits for it (`weekOfChange`). */
  readonly nextTimeZone: TimeZone;
}

interface Deps {
  readonly store: SquadStore;
}

/** The squad's time zone in its week at `moment`. */
export async function squadTimeZone(
  deps: Deps,
  input: { readonly squad: SquadId; readonly viewer: MemberId; readonly moment: Date },
): Promise<SquadTimeZone> {
  await findSquad(deps, { squad: input.squad, viewer: input.viewer });
  const settings = await settingsOf(deps, input.squad);
  const week = weekAt(settings, input.moment);
  return {
    timeZone: zoneFor(settings, week),
    nextTimeZone: zoneFor(settings, weekAfter(week)),
  };
}

async function settingsOf(deps: Deps, squad: SquadId) {
  return (await deps.store.timeZones([squad])).get(squad) ?? [];
}

/**
 * Sets the squad's time zone, for its captain. It counts at once (Tracy, 2026-11-08), so this
 * week's 战报 freezes Sunday 8pm on the new clock, unless Sunday 8pm has already passed on the old
 * clock or the new one when the captain changes it: then it counts from the next week (Tracy,
 * 2026-11-13), so a change never freezes this week's 战报 early or reopens one that froze. Which
 * week, `weekOfChange`. Saving the zone the squad already keeps changes nothing.
 */
export async function setSquadTimeZone(
  deps: Deps,
  input: {
    readonly squad: SquadId;
    readonly member: MemberId;
    readonly timeZone: string;
    readonly moment: Date;
  },
): Promise<SquadTimeZone> {
  await findSquad(deps, { squad: input.squad, viewer: input.member });
  if (!isKnownTimeZone(input.timeZone)) throw new SquadTimeZoneUnknownError(input.timeZone);
  const week = weekOfChange(await settingsOf(deps, input.squad), {
    zone: input.timeZone,
    moment: input.moment,
  });
  const outcome = await deps.store.setTimeZone({
    squad: input.squad,
    actor: input.member,
    timeZone: input.timeZone,
    week,
  });
  if (outcome === 'notCaptain') throw new NotSquadCaptainError();
  return squadTimeZone(deps, { squad: input.squad, viewer: input.member, moment: input.moment });
}
