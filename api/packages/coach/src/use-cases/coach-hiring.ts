import type { Coach, CoachId } from '../domain/coach.js';
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
  /**
   * Hires an offered coach for a squad, firing the one it has first (换教练, one step). Safe to
   * repeat: `changed` is false when the squad has that coach already. Throws
   * `CoachNotOfferedError` or `CoachSquadNotFoundError`.
   */
  change(input: {
    readonly squad: SquadId;
    readonly coach: CoachId;
    readonly by: MemberId;
  }): Promise<{ readonly coach: Coach; readonly changed: boolean }>;
  /** The squad's coach now and since when, retired or not, or `undefined` when it has none. */
  current(squad: SquadId): Promise<{ readonly coach: Coach; readonly since: Date } | undefined>;
  /** The coaches a squad can hire now (教练市场), by id. */
  offered(): Promise<readonly Coach[]>;
}

export function createCoachHiring(deps: {
  readonly hiring: CoachHiringStore;
  readonly catalog: CoachCatalogStore;
}): CoachHiring {
  const offered = async () => (await deps.catalog.list()).filter((coach) => coach.offered);
  const offeredOne = async (id: CoachId) => {
    const found = (await offered()).find((coach) => coach.id === id);
    if (found === undefined) throw new CoachNotOfferedError(id);
    return found;
  };
  const currentOf = async (squad: SquadId) => {
    const hired = await deps.hiring.coachOf(squad);
    if (hired === undefined) return undefined;
    const coach = (await deps.catalog.list()).find(({ id }) => id === hired.coach);
    return coach === undefined ? undefined : { coach, since: hired.since };
  };
  return {
    offered,

    async hire({ squad, coach, by }) {
      await offeredOne(coach);
      const outcome = await deps.hiring.hire({ squad, coach, by });
      if (outcome === 'noSquad') throw new CoachSquadNotFoundError();
      if (outcome === 'hasCoach') {
        throw new CoachAlreadyHiredError((await deps.hiring.coachOf(squad))?.coach ?? coach);
      }
      return { coach };
    },

    async fire({ squad, by }) {
      const fired = await deps.hiring.fire({ squad, by });
      if (fired === undefined) throw new NoCoachHiredError();
      return { fired };
    },

    async change({ squad, coach, by }) {
      // The coach the squad has already, even one retired since: a retry changes nothing.
      const current = await currentOf(squad);
      if (current?.coach.id === coach) return { coach: current.coach, changed: false };
      const hired = await offeredOne(coach);
      const outcome = await deps.hiring.replace({ squad, coach, by });
      if (outcome === 'noSquad') throw new CoachSquadNotFoundError();
      return { coach: hired, changed: outcome === 'hired' };
    },

    current: currentOf,
  };
}
