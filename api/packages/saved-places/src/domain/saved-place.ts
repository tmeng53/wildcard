import { z } from 'zod';

import type { Place, PlaceKey } from '@wildcard/place-ids';
import { typedText } from '@wildcard/typed-text';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/** The member's note on a saved place: trimmed, 1 to 60 characters, one line. */
export const SavedPlaceNote = typedText({
  max: 60,
  oneLine: true,
  description: 'Trimmed, then 1 to 60 characters as people see them, on one line.',
});

/** A place a member saved, as it stands now. */
export interface SavedPlace {
  readonly key: PlaceKey;
  readonly place: Place;
  readonly note?: string;
  /** When they saved it, kept through later changes to its note. */
  readonly savedAt: Date;
}

/** How many places a member may keep saved at once. */
export const MAX_SAVED_PLACES = 200;
