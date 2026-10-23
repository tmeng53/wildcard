import { z } from 'zod';

/**
 * The moves a character can play when it collects an award, as the app names its clips. `cheer`
 * is the member's own persona's cheer; the rest are moves every character shares. A move added
 * here must exist in the app first (the character art in ios/Packages/Avatar), or the app falls
 * back to `cheer`. What each looks like, for the model, is a setting (AwardSettings).
 */
export const AwardMove = z.enum([
  'cheer',
  'pump',
  'pose',
  'warmup',
  'stretch',
  'doze',
  'flat',
  'laugh',
  'wave',
  'fullbelly',
]);
export type AwardMove = z.infer<typeof AwardMove>;

/** How teammates react to the best 请假条. */
export const SquadMove = z.enum(['laugh', 'pump', 'wave']);
export type SquadMove = z.infer<typeof SquadMove>;

/** The squad's move on the ending: `pump` or `wave` when it hit its plan, else `warmup`, `stretch` or `pump`. */
export const EndingMove = z.enum(['pump', 'wave', 'warmup', 'stretch']);
export type EndingMove = z.infer<typeof EndingMove>;
