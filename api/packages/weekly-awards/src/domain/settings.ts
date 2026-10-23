import { z } from 'zod';

import { AwardMove } from './moves.js';

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

/** The settings, whole, as stored and logged: every move has its description. */
export const AwardSettings = z.strictObject({
  version: z.literal(1),
  ...fields,
  moves: z.record(AwardMove, MoveDescription),
});
export type AwardSettings = z.infer<typeof AwardSettings>;

/** What an admin changes: any of the settings, and any moves' descriptions, the rest as they are. */
export const AwardSettingsChange = z
  .strictObject({
    ...fields,
    moves: z
      .partialRecord(AwardMove, MoveDescription)
      .describe('What a move looks like and which awards it suits, for the model, by move id.'),
  })
  .partial();
export type AwardSettingsChange = z.infer<typeof AwardSettingsChange>;
