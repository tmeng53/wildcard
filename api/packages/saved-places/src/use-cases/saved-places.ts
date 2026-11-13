import { isDeepStrictEqual } from 'node:util';

import { placeKey, type Place, type PlaceKey } from '@wildcard/place-ids';

import { MAX_SAVED_PLACES, type MemberId, type SavedPlace } from '../domain/saved-place.js';
import { PlaceWithoutKeyError, TooManySavedPlacesError } from '../errors.js';
import type { Clock, SavedPlaceStore } from '../ports.js';

/** What a member saved (收藏): places with a note, seen only by them. */
export interface SavedPlaces {
  /** The places `member` has saved, newest saved first. */
  list(member: MemberId): Promise<SavedPlace[]>;
  /**
   * Saves `place` for `member` with `note` (none when left out), or changes the note of one
   * they saved already. Saving it again unchanged logs nothing. Returns it as it stands.
   */
  save(input: {
    readonly member: MemberId;
    readonly place: Place;
    readonly note?: string | undefined;
  }): Promise<SavedPlace>;
  /** Removes the place `key` from what `member` saved; nothing when it isn't saved. */
  remove(input: { readonly member: MemberId; readonly key: PlaceKey }): Promise<void>;
}

export function createSavedPlaces(deps: {
  readonly store: SavedPlaceStore;
  readonly clock: Clock;
}): SavedPlaces {
  const { store, clock } = deps;
  return {
    list: (member) => store.listFor(member),

    async save({ member, place, note }) {
      const key = placeKey(place);
      if (key === undefined) throw new PlaceWithoutKeyError();
      const saved = await store.listFor(member);
      const existing = saved.find((each) => each.key === key);
      if (
        existing !== undefined &&
        isDeepStrictEqual(existing.place, place) &&
        existing.note === note
      ) {
        return existing;
      }
      if (existing === undefined && saved.length >= MAX_SAVED_PLACES) {
        throw new TooManySavedPlacesError();
      }
      const at = clock();
      await store.save({ member, key, place, ...(note === undefined ? {} : { note }), at });
      return {
        key,
        place,
        ...(note === undefined ? {} : { note }),
        savedAt: existing?.savedAt ?? at,
      };
    },

    async remove({ member, key }) {
      const saved = await store.listFor(member);
      if (!saved.some((each) => each.key === key)) return;
      await store.remove({ member, key, at: clock() });
    },
  };
}
