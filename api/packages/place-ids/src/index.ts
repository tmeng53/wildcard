import { z } from 'zod';

import { nameText } from '@wildcard/typed-text';

// @wildcard/place-ids: a place as the app sends it, shared by the modules that keep places (the
// check-ins tagged with one, the places a member saved).
//
// The place a member tags a 训练 or a meal with (Tracy, 2026-11-12): one they picked from Apple
// Maps on the phone, or one a squad's member added, never where the phone was. The squad sees
// its name and opens it in Maps; the coach reads only its name.

/** A place's name as Apple Maps gives it: trimmed, 1 to 100 characters, one line. */
const PlaceName = nameText({
  max: 100,
  description: 'Trimmed, then 1 to 100 characters as people see them, on one line.',
});

export const Place = z
  .strictObject({
    name: PlaceName,
    appleId: z
      .string()
      .min(1)
      .max(200)
      .optional()
      .meta({ description: "Apple Maps' identifier for the place, when Maps gave one." }),
    squadPlaceId: z.uuid().optional().meta({
      description: "The id of the place a squad's member added, when it is one (and not Maps').",
    }),
    category: z
      .string()
      .regex(/^[A-Za-z]{1,60}$/)
      .optional()
      .meta({ description: "Apple Maps' point-of-interest category, such as `fitnessCenter`." }),
    latitude: z.number().min(-90).max(90),
    longitude: z.number().min(-180).max(180),
  })
  .meta({
    id: 'Place',
    description:
      "A place the member picked in Apple Maps (its name, Maps' id and category) or one their " +
      "squad added (its id), and the place's own coordinates, never the phone's.",
  });
export type Place = z.infer<typeof Place>;

/**
 * Which place: `apple:` and Apple Maps' identifier, or `squad:` and the id of a place a squad's
 * member added. The one way the app and every module address a place (its page, its ratings,
 * a member's 收藏).
 */
export const PlaceKey = z
  .string()
  .regex(
    /^(apple:[A-Za-z0-9._-]{1,200}|squad:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/,
  )
  .brand<'PlaceKey'>()
  .meta({
    description:
      "Which place: `apple:` and Apple Maps' identifier, or `squad:` and the id of a place a " +
      "squad's member added.",
    example: 'apple:I6FD7682FD36BB3BE',
  });
export type PlaceKey = z.infer<typeof PlaceKey>;

/** The key of `place`, or none when Maps gave it no identifier it can be found by again. */
export function placeKey(place: Place): PlaceKey | undefined {
  if (place.appleId === undefined) return undefined;
  const key = PlaceKey.safeParse(`apple:${place.appleId}`);
  return key.success ? key.data : undefined;
}
