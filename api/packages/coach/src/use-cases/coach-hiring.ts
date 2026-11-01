import type { CoachId } from '../domain/coach.js';
import type { MemberId, SquadId } from '../domain/settings.js';
import {
  CoachAlreadyHiredError,
  CoachNotOfferedError,
  CoachSquadNotFoundError,
  NoCoachHiredError,
} from '../errors.js';
import type { CoachCatalogStore, CoachHiringStore } from '../ports.js';

/** Squads hiring and firing their coach: one at a time, each change logged. */
export interface CoachHiring {
  /**
   * Hires an offered coach for a squad with none. Throws `CoachNotOfferedError`,
   * `CoachAlreadyHiredError` (fire it first) or `CoachSquadNotFoundError`.
   */
  hire(input: {
    readonly squad: SquadId;
    readonly coach: CoachId;
    readonly by: MemberId;
  }): Promise<{ readonly coach: CoachId }>;
  /**
   * Fires the squad's coach, keeping the squad's memory for the next one. Throws
   * `NoCoachHiredError` when it has none.
   */
  fire(input: { readonly squad: SquadId; readonly by: MemberId }): Promise<{
    readonly fired: CoachId;
  }>;
}

export function createCoachHiring(deps: {
  readonly hiring: CoachHiringStore;
  readonly catalog: CoachCatalogStore;
}): CoachHiring {
  return {
    async hire({ squad, coach, by }) {
      const offered = (await deps.catalog.list()).some(
        ({ id, offered: isOffered }) => id === coach && isOffered,
      );
      if (!offered) throw new CoachNotOfferedError(coach);
      const outcome = await deps.hiring.hire({ squad, coach, by });
      if (outcome === 'noSquad') throw new CoachSquadNotFoundError();
      if (outcome === 'hasCoach') {
        throw new CoachAlreadyHiredError((await deps.hiring.coachOf(squad)) ?? coach);
      }
      return { coach };
    },

    async fire({ squad, by }) {
      const fired = await deps.hiring.fire({ squad, by });
      if (fired === undefined) throw new NoCoachHiredError();
      return { fired };
    },
  };
}
