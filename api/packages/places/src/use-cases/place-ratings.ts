import type { MemberId, PlaceKey, Stars } from '../domain/place-rating.js';
import type { Clock, PlaceRatingStore } from '../ports.js';

/** Members' scores for the places they train at. */
export interface PlaceRatings {
  /**
   * Gives `member`'s score for `place`, standing over any earlier one. The same score as the
   * one standing adds nothing, so a retry is safe.
   */
  rate(input: {
    readonly member: MemberId;
    readonly place: PlaceKey;
    readonly stars: Stars;
  }): Promise<'created' | 'unchanged'>;
  /** Each of `members`' standing score for `place`. */
  of(input: {
    readonly place: PlaceKey;
    readonly members: readonly MemberId[];
  }): Promise<ReadonlyMap<MemberId, Stars>>;
  /** Each of `members`' standing score for each of `places`, by place. */
  ofAll(input: {
    readonly places: readonly PlaceKey[];
    readonly members: readonly MemberId[];
  }): Promise<ReadonlyMap<PlaceKey, ReadonlyMap<MemberId, Stars>>>;
}

export function createPlaceRatings(deps: {
  readonly store: PlaceRatingStore;
  readonly clock: Clock;
}): PlaceRatings {
  return {
    async rate({ member, place, stars }) {
      const standing = await deps.store.latest({ place, members: [member] });
      if (standing.get(member) === stars) return 'unchanged';
      await deps.store.add({ member, place, stars, at: deps.clock() });
      return 'created';
    },
    of: ({ place, members }) =>
      members.length === 0 ? Promise.resolve(new Map()) : deps.store.latest({ place, members }),
    ofAll: ({ places, members }) =>
      places.length === 0 || members.length === 0
        ? Promise.resolve(new Map())
        : deps.store.latestForAll({ places, members }),
  };
}
