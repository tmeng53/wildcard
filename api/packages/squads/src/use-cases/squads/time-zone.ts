import { isKnownTimeZone, type TimeZone } from '@wildcard/time-zones';

import type { MemberId, SquadId } from '../../domain/squad.js';
import { weekAt, zoneFor } from '../../domain/time-zone.js';
import { weekAfter } from '../../domain/weekly-goal.js';
import { NotSquadCaptainError, SquadTimeZoneUnknownError } from '../../errors.js';
import type { SquadStore } from '../../ports.js';
import { findSquad } from './find-squad.js';

/** A squad's time zone (小队时区) this week and next, as its members see it. */
export interface SquadTimeZone {
  readonly timeZone: TimeZone;
  /** Next week's: a captain's change counts from the next week. */
  readonly nextTimeZone: TimeZone;
}

interface Deps {
  readonly store: SquadStore;
}

/** The squad's time zone in its week at `moment` and the week after. */
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
 * Sets the squad's time zone, for its captain. It counts from the week after the squad's week at
 * `moment` on its own clock, so a week's 战报 never moves while the squad plays it. Saving the zone next week has
 * already changes nothing.
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
  const week = weekAt(await settingsOf(deps, input.squad), input.moment);
  const outcome = await deps.store.setTimeZone({
    squad: input.squad,
    actor: input.member,
    timeZone: input.timeZone,
    week: weekAfter(week),
  });
  if (outcome === 'notCaptain') throw new NotSquadCaptainError();
  return squadTimeZone(deps, { squad: input.squad, viewer: input.member, moment: input.moment });
}
