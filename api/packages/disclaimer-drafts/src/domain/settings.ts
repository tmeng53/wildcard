import { z } from 'zod';

// What drafts are written with, as kept in the database and changed by an admin: so the prompt,
// the model and the dials change without a deploy.

/**
 * A model, as `provider/model` (`openai/gpt-6-luna`). Which providers exist is the server's to
 * know (it holds their keys), so this module passes the name along as it is.
 */
export const ModelName = z.string().min(3).max(120).brand<'ModelName'>();
export type ModelName = z.infer<typeof ModelName>;

const fields = {
  writing: z
    .boolean()
    .describe('Whether drafts are written at all. Off, every request gets the app’s dice.'),
  model: ModelName.describe('The model that writes them, as provider/model.'),
  instructions: z
    .string()
    .min(1)
    .max(20_000)
    .describe('The standing instructions (system prompt), Chinese, as the product spec has them.'),
  batchesPerDay: z
    .int()
    .min(1)
    .max(100)
    .describe('Batches a member may ask for in 24 hours: the first and each 换一批.'),
  memeChance: z
    .number()
    .min(0)
    .max(1)
    .describe('How often a request gets one of this week’s memes that suits its style, 0 to 1.'),
};

/** The settings, whole, as stored and logged. */
export const DraftSettings = z.strictObject({ version: z.literal(1), ...fields });
export type DraftSettings = z.infer<typeof DraftSettings>;

/** What an admin changes: any of the settings, the rest staying as they are. */
export const DraftSettingsChange = z.strictObject(fields).partial();
export type DraftSettingsChange = z.infer<typeof DraftSettingsChange>;
