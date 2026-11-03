import { z } from 'zod';

import { AwardMove, CHEER } from './moves.js';

// What the weekly awards are written with, as kept in the database and changed by an admin: so
// the prompt, the model and the moves' descriptions change without a deploy.

/**
 * A model, as `provider/model` (`openai/gpt-6-luna`). Which providers exist is the server's to
 * know (it holds their keys), so this module passes the name along as it is.
 */
export const ModelName = z.string().min(3).max(120).brand<'ModelName'>();
export type ModelName = z.infer<typeof ModelName>;

const MoveDescription = z.string().min(1).max(200);

const fields = {
  model: ModelName.describe('The model that writes them, as provider/model.'),
  instructions: z
    .string()
    .min(1)
    .max(20_000)
    .describe('The standing instructions (system prompt), Chinese, as the product spec has them.'),
};

/**
 * The settings, whole, as stored and logged. `moves` is the list the model picks from: every
 * move offered, with what it looks like; `cheer` is always there.
 */
export const AwardSettings = z.strictObject({
  version: z.literal(1),
  ...fields,
  moves: z
    .record(AwardMove, MoveDescription)
    .refine((moves) => CHEER in moves, { message: `The moves always describe \`${CHEER}\`.` }),
});
export type AwardSettings = z.infer<typeof AwardSettings>;

/**
 * What an admin changes: any of the settings, and any moves' descriptions, the rest as they are.
 * A move not described yet is added, and the model may pick it from the next awards.
 */
export const AwardSettingsChange = z
  .strictObject({
    ...fields,
    moves: z
      .record(AwardMove, MoveDescription)
      .describe(
        'What a move looks like and which awards it suits, for the model, by move id. A new id ' +
          'adds the move; use only ids the app has art for (it plays the persona’s cheer for others).',
      ),
  })
  .partial();
export type AwardSettingsChange = z.infer<typeof AwardSettingsChange>;

/** The moves the settings offer, by id: `cheer` first, then the rest in order. */
export function offeredMoves(moves: AwardSettings['moves']): [AwardMove, ...AwardMove[]] {
  return [
    CHEER,
    ...Object.keys(moves)
      .filter((id) => id !== CHEER)
      .sort(),
  ];
}
