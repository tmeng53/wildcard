import { z } from 'zod';

import { nameText } from '@wildcard/typed-text';

// The place a member tags a 训练 or a meal with (Tracy, 2026-11-12): one they picked from Apple
// Maps on the phone, never where the phone was. The squad sees its name and opens it in Maps;
// the coach reads only its name.

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
      "A place the member picked in Apple Maps: its name, Maps' id and category, and the " +
      "place's own coordinates, never the phone's.",
  });
export type Place = z.infer<typeof Place>;
