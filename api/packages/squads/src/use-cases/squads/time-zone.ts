import { isKnownTimeZone, type TimeZone } from '@wildcard/time-zones';

import type { SceneWeek } from '../../domain/scene.js';
import type { MemberId, SquadId } from '../../domain/squad.js';
import { zoneFor } from '../../domain/time-zone.js';
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

/** The squad's time zone in the viewer's week (its Monday) and the week after. */
export async function squadTimeZone(
  deps: Deps,
  input: { readonly squad: SquadId; readonly viewer: MemberId; readonly week: SceneWeek },
): Promise<SquadTimeZone> {
  await findSquad(deps, { squad: input.squad, viewer: input.viewer });
  const settings = (await deps.store.timeZones([input.squad])).get(input.squad) ?? [];
  return {
    timeZone: zoneFor(settings, input.week),
    nextTimeZone: zoneFor(settings, weekAfter(input.week)),
  };
}

/**
 * Sets the squad's time zone, for its captain. It counts from the week after the captain's week
 * now, so a week's 战报 never moves while the squad plays it. Saving the zone next week has
 * already changes nothing.
 */
export async function setSquadTimeZone(
  deps: Deps,
  input: {
    readonly squad: SquadId;
    readonly member: MemberId;
    readonly timeZone: string;
    readonly week: SceneWeek;
  },
): Promise<SquadTimeZone> {
  await findSquad(deps, { squad: input.squad, viewer: input.member });
  if (!isKnownTimeZone(input.timeZone)) throw new SquadTimeZoneUnknownError(input.timeZone);
  const outcome = await deps.store.setTimeZone({
    squad: input.squad,
    actor: input.member,
    timeZone: input.timeZone,
    week: weekAfter(input.week),
  });
  if (outcome === 'notCaptain') throw new NotSquadCaptainError();
  return squadTimeZone(deps, { squad: input.squad, viewer: input.member, week: input.week });
}
