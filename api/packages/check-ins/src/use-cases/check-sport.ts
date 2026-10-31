import { CUSTOM_SPORT } from '@wildcard/sport-ids';

import { SportNotListedError } from '../errors.js';
import type { SportList } from '../ports.js';

/** A listed sport, or 其他. */
export async function checkSport(sports: SportList, sport: string): Promise<void> {
  if (sport !== CUSTOM_SPORT && !(await sports.isListed(sport))) {
    throw new SportNotListedError(sport);
  }
}
