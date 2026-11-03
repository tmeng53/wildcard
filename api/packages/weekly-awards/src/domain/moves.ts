import { z } from 'zod';

/**
 * A move a character can play when it collects an award, by the id the app names its art by:
 * `cheer` (the member's own persona's cheer), a move every character shares (`pump`), a 动态
 * reaction move (`chin-up`) or a sport kit's move, played holding that sport's prop (`swim`).
 * Which moves the model picks from is data: the ids `weekly_award_settings.moves` describes, so
 * a move the app draws is offered once an admin (or a migration) gives it a description, with
 * no change here. A test checks every move the app's art has is described. The app plays its
 * persona's cheer for a move it doesn't know.
 */
export const AwardMove = z
  .string()
  .regex(/^[a-z][a-z-]{0,39}$/u)
  .meta({ description: 'A move id, as the app names its art: lowercase letters and hyphens.' });
export type AwardMove = z.infer<typeof AwardMove>;

/** The move every character has: its persona's own cheer, never left out of the settings. */
export const CHEER: AwardMove = 'cheer';
