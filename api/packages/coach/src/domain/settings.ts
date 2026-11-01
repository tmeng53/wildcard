import { z } from 'zod';

// What every coach runs with, as kept in the database and changed by an admin: so coaching,
// the model, the rules and the prices change without a deploy.

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/** A squad's id, lower-cased as Postgres stores a uuid. */
export const SquadId = z
  .uuid()
  .transform((id) => id.toLowerCase())
  .brand<'SquadId'>();
export type SquadId = z.infer<typeof SquadId>;

/**
 * The coach's model, as `openai/model`. The coach runs on the OpenAI Agents SDK, so it is an
 * OpenAI model; the database checks the same.
 */
export const CoachModel = z
  .string()
  .regex(/^openai\/[A-Za-z0-9._:-]{1,100}$/)
  .brand<'CoachModel'>()
  .describe('openai/model, such as openai/gpt-6-luna.');
export type CoachModel = z.infer<typeof CoachModel>;

/** US dollars in millionths, per million tokens. */
const MicrosPerMillion = z.int().min(0).max(2_000_000_000);

const fields = {
  coaching: z
    .boolean()
    .describe(
      'Whether coaches wake at all. On, every squad that hired a coach has one; off, none does and nothing is sent.',
    ),
  model: CoachModel,
  rules: z
    .string()
    .min(1)
    .max(20_000)
    .describe('The rules every coach follows, Chinese; each coach’s soul comes after them.'),
  inputMicrosPerMillion: MicrosPerMillion.describe(
    'The model’s price for input tokens: US dollars in millionths per million tokens.',
  ),
  cachedInputMicrosPerMillion: MicrosPerMillion.describe(
    'The model’s price for input tokens the provider had cached from an earlier request with the same beginning: US dollars in millionths per million tokens.',
  ),
  outputMicrosPerMillion: MicrosPerMillion.describe(
    'The model’s price for output tokens: US dollars in millionths per million tokens.',
  ),
};

/** The settings, whole, as stored and logged. */
export const CoachSettings = z.strictObject({ version: z.literal(1), ...fields });
export type CoachSettings = z.infer<typeof CoachSettings>;

/** What an admin changes: any of the settings, the rest staying as they are. */
export const CoachSettingsChange = z.strictObject(fields).partial();
export type CoachSettingsChange = z.infer<typeof CoachSettingsChange>;
