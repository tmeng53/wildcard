import type { MemberId, PlaceKey, PlaceRating, Stars } from './domain/place-rating.js';
import type { SquadId, SquadPlace, SquadPlaceId } from './domain/squad-place.js';

/** Where scores are kept: every one given, never changed, the latest per member standing. */
export interface PlaceRatingStore {
  /** Adds a score. */
  add(rating: PlaceRating): Promise<void>;
  /** Each of `members`' latest score for `place`, for those who gave one. */
  latest(query: {
    readonly place: PlaceKey;
    readonly members: readonly MemberId[];
  }): Promise<ReadonlyMap<MemberId, Stars>>;
  /** Each of `members`' latest score for each of `places`, by place. */
  latestForAll(query: {
    readonly places: readonly PlaceKey[];
    readonly members: readonly MemberId[];
  }): Promise<ReadonlyMap<PlaceKey, ReadonlyMap<MemberId, Stars>>>;
}

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
