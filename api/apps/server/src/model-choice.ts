import { z } from 'zod';

// Which language model writes something is a module's setting, kept in the database as
// `provider/model`. These are the providers the server has an adapter (and a key setting) for.

/** A model the server can call: `provider/model`, as the settings name it and the database checks. */
export const ModelChoice = z
  .string()
  .regex(/^(openai|anthropic)\/[A-Za-z0-9._:-]{1,100}$/)
  .describe('provider/model: openai/… or anthropic/…, such as openai/gpt-6-luna.');

export type Provider = 'openai' | 'anthropic';
