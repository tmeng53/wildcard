import type { MemberId } from '../domain/place-rating.js';
import type { SquadId, SquadPlace, SquadPlaceId, SquadPlaceKind } from '../domain/squad-place.js';
import { SquadNotJoinedError, SquadPlaceIdConflictError } from '../errors.js';
import type { Clock, SquadMembership, SquadPlaceStore } from '../ports.js';

/** Places squads' members add themselves, for the whole squad to tag posts with. */
export interface SquadPlaces {
  /**
   * Adds a place to the member's squad under the id the app made, so a retry adds it once.
   * Throws `SquadNotJoinedError` outside the squad, and `SquadPlaceIdConflictError` when the id
   * is another place.
   */
  add(input: {
    readonly id: SquadPlaceId;
    readonly squad: SquadId;
    readonly member: MemberId;
    readonly name: string;
    readonly kind: SquadPlaceKind;
    readonly latitude: number;
    readonly longitude: number;
  }): Promise<{ readonly place: SquadPlace; readonly created: boolean }>;
  /** Every place the squad's members added, the earliest first, for a member of it. */
  list(input: { readonly squad: SquadId; readonly viewer: MemberId }): Promise<SquadPlace[]>;
}

const sameContents = (a: SquadPlace, b: Omit<SquadPlace, 'addedBy' | 'addedAt'>) =>
  a.squad === b.squad &&
  a.name === b.name &&
  a.kind === b.kind &&
  a.latitude === b.latitude &&
  a.longitude === b.longitude;

export function createSquadPlaces(deps: {
  readonly store: SquadPlaceStore;
  readonly membership: SquadMembership;
  readonly clock: Clock;
}): SquadPlaces {
  async function joined(member: MemberId, squad: SquadId) {
    if (!(await deps.membership.squadIdsOf(member)).has(squad)) {
      throw new SquadNotJoinedError(squad);
    }
  }
  return {
    async add({ member, ...fields }) {
      await joined(member, fields.squad);
      const place: SquadPlace = { ...fields, addedBy: member, addedAt: deps.clock() };
      if ((await deps.store.add(place)) === 'created') return { place, created: true };
      const saved = await deps.store.find(fields.id);
      if (saved === undefined || !sameContents(saved, fields)) {
        throw new SquadPlaceIdConflictError(fields.id);
      }
      return { place: saved, created: false };
    },
    async list({ squad, viewer }) {
      await joined(viewer, squad);
      return deps.store.listForSquad(squad);
    },
  };
}
