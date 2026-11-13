import type { MemberId, PlaceKey, PlaceRating, Stars } from './domain/place-rating.js';

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

/** The current time. */
export type Clock = () => Date;
