import { PlaceKey } from '@wildcard/place-ids';
import { z } from 'zod';

// How members rate the places they train at (Tracy, 2026-11-12): one score, 1 to 5 tickets, a
// member and a place, which they may change; the latest stands. Squadmates see the average of
// their squad's members. Meals are rated on the meal itself (the check-ins module), never here.

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

export { PlaceKey };

/** The key of a place Maps gave `appleId`. */
export function appleKey(appleId: string): PlaceKey | undefined {
  const parsed = PlaceKey.safeParse(`apple:${appleId}`);
  return parsed.success ? parsed.data : undefined;
}

/** The key of the place a squad's member added under `id`. */
export function squadKey(id: string): PlaceKey | undefined {
  const parsed = PlaceKey.safeParse(`squad:${id.toLowerCase()}`);
  return parsed.success ? parsed.data : undefined;
}

export const Stars = z.int().min(1).max(5).meta({ description: 'The score, 1 to 5.' });
export type Stars = z.infer<typeof Stars>;

/** One member's score for one place, as given at `at`. */
export interface PlaceRating {
  readonly member: MemberId;
  readonly place: PlaceKey;
  readonly stars: Stars;
  readonly at: Date;
}
