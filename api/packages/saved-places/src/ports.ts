import type { Place, PlaceKey } from '@wildcard/place-ids';

import type { MemberId, SavedPlace } from './domain/saved-place.js';

/** Where saved places are kept: a log of every save and removal, the latest per place standing. */
export interface SavedPlaceStore {
  /** The places `member` has saved now, newest saved first. */
  listFor(member: MemberId): Promise<SavedPlace[]>;
  /** Logs that `member` saved `place` with `note` (none when left out) at `at`. */
  save(entry: {
    readonly member: MemberId;
    readonly key: PlaceKey;
    readonly place: Place;
    readonly note?: string;
    readonly at: Date;
  }): Promise<void>;
  /** Logs that `member` removed the place `key` at `at`. */
  remove(entry: {
    readonly member: MemberId;
    readonly key: PlaceKey;
    readonly at: Date;
  }): Promise<void>;
}

/** The current time. */
export type Clock = () => Date;
