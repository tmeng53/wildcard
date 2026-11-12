import type { TokenUsage } from '@wildcard/language-model';
import { z } from 'zod';

/** What a model call was for: the line it is counted under in the ledger. */
export const AiFeature = z.enum([
  'coach-wake',
  'coach-letter',
  'coach-preview',
  'disclaimer-drafts',
  'weekly-awards',
]);
export type AiFeature = z.infer<typeof AiFeature>;

/** A model as every module's settings name it: `provider/model`. */
export const ModelName = z
  .string()
  .regex(/^(openai|anthropic)\/[A-Za-z0-9._:-]{1,100}$/)
  .describe('provider/model, such as openai/gpt-6-luna.');
export type ModelName = z.infer<typeof ModelName>;

/** US dollars in millionths, per million tokens. */
const MicrosPerMillion = z.int().min(0).max(2_000_000_000);

/** What a model's tokens cost, as its provider charges them. */
export const ModelPrice = z.strictObject({
  inputMicrosPerMillion: MicrosPerMillion.describe(
    'Input tokens: US dollars in millionths per million tokens.',
  ),
  cachedInputMicrosPerMillion: MicrosPerMillion.describe(
    'Input tokens the provider had cached from an earlier request with the same beginning: US dollars in millionths per million tokens.',
  ),
  outputMicrosPerMillion: MicrosPerMillion.describe(
    'Output tokens, thinking included: US dollars in millionths per million tokens.',
  ),
});
export type ModelPrice = z.infer<typeof ModelPrice>;

/** What tokens cost at a model's price, in US dollars' millionths, rounded up. */
export function costMicros(usage: TokenUsage, price: ModelPrice): number {
  const cached = Math.min(usage.cachedInputTokens, usage.inputTokens);
  return Math.ceil(
    ((usage.inputTokens - cached) * price.inputMicrosPerMillion +
      cached * price.cachedInputMicrosPerMillion +
      usage.outputTokens * price.outputMicrosPerMillion) /
      1_000_000,
  );
}

/** What a squad's calls added up to, for the admins. */
export interface UsageTotal {
  /** The calls (a coach's wake or letter is one, whatever requests it made). */
  readonly calls: number;
  readonly requests: number;
  readonly inputTokens: number;
  /** Those of the input tokens the provider had cached. */
  readonly cachedInputTokens: number;
  readonly outputTokens: number;
  /** US dollars in millionths. */
  readonly costMicros: number;
}
