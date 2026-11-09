import { isKnownTimeZone, mondayOf, wallClockAt, type TimeZone } from '@wildcard/time-zones';

import type { MemberId, SquadId } from '../../domain/squad.js';
import { SceneWeek } from '../../domain/scene.js';
import { weekAt, zoneFor } from '../../domain/time-zone.js';
import { NotSquadCaptainError, SquadTimeZoneUnknownError } from '../../errors.js';
import type { SquadStore } from '../../ports.js';
import { findSquad } from './find-squad.js';

/** A squad's time zone (小队时区), as its members see it. */
export interface SquadTimeZone {
  readonly timeZone: TimeZone;
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
  return { timeZone: zoneFor(settings, weekAt(settings, input.moment)) };
}

async function settingsOf(deps: Deps, squad: SquadId) {
  return (await deps.store.timeZones([squad])).get(squad) ?? [];
}

/**
 * Sets the squad's time zone, for its captain. It counts at once (Tracy, 2026-11-08), so this
 * week's 战报 freezes Sunday 8pm on the new clock: from the squad's week at `moment`, or from the
 * week before when it is still that week on the new clock (a change made on the squad's Monday that
 * is Sunday in the new zone), so the new zone is the squad's zone straight away on every clock.
 * Saving the zone the squad already keeps changes nothing.
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
  const now = weekAt(await settingsOf(deps, input.squad), input.moment);
  const there = SceneWeek.parse(mondayOf(wallClockAt(input.moment, input.timeZone).day));
  const week = there < now ? there : now;
  const outcome = await deps.store.setTimeZone({
    squad: input.squad,
    actor: input.member,
    timeZone: input.timeZone,
    week,
  });
  if (outcome === 'notCaptain') throw new NotSquadCaptainError();
  return squadTimeZone(deps, { squad: input.squad, viewer: input.member, moment: input.moment });
}
