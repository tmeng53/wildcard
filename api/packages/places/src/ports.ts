import type { MemberId } from './domain/ids.js';
import type { SquadId, SquadPlace, SquadPlaceId } from './domain/squad-place.js';

/** Where the places squads' members added are kept: never changed once added. */
export interface SquadPlaceStore {
  /** Adds a place, unless one with its id is there already. */
  add(place: SquadPlace): Promise<'created' | 'exists'>;
  /** The place under `id`, whichever squad it is. */
  find(id: SquadPlaceId): Promise<SquadPlace | undefined>;
  /** Every place `squad`'s members added, the earliest first. */
  listForSquad(squad: SquadId): Promise<SquadPlace[]>;
}

/** Who is in which squad now. The squads module keeps that; places only ask. */
export interface SquadMembership {
  /** The squads `member` is in now. */
  squadIdsOf(member: MemberId): Promise<ReadonlySet<SquadId>>;
}

/** The current time. */
export type Clock = () => Date;
