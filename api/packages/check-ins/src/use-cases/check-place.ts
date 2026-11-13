import { placeOf, type CheckInRecord } from '../domain/check-in.js';
import { SquadPlaceNotFoundError } from '../errors.js';
import type { SquadPlaceOf } from '../ports.js';

/** A post tagged with a squad's place names one its squads have. */
export async function checkSquadPlace(
  squadPlaceOf: SquadPlaceOf,
  checkIn: CheckInRecord,
): Promise<void> {
  const place = placeOf(checkIn)?.squadPlaceId;
  if (place === undefined) return;
  const known =
    checkIn.audience.length > 0 && (await squadPlaceOf({ place, squads: checkIn.audience }));
  if (!known) throw new SquadPlaceNotFoundError(place);
}
