import Anthropic from '@anthropic-ai/sdk';
import { zodOutputFormat } from '@anthropic-ai/sdk/helpers/zod';
import { DisclaimerWriterUnavailableError } from '@wildcard/disclaimer-drafts';

import type { ProviderModels } from './language-models.js';

/**
 * A member is waiting with the button pressed: past this, the app's dice are the better answer.
 * Counted per attempt; with one retry a request takes at most twice this.
 */
const TIMEOUT_MS = 8_000;

/**
 * Three drafts of up to 80 characters fit in a few hundred tokens; the rest is room for Haiku's
 * adaptive thinking, so an answer is never cut off.
 */
const MAX_TOKENS = 4_096;

/** The language model on Anthropic's Claude API, with structured output. */
export function createAnthropicLanguageModel(options: {
  readonly apiKey: string;
  /**
   * How long one attempt may take, and how many tokens its answer may use (reasoning
   * included). A member waiting on drafts gets the defaults; a job writing a squad's awards
   * gets more of both.
   */
  readonly timeoutMs?: number;
  readonly maxOutputTokens?: number;
  /** Tests only: where requests go, instead of Anthropic. */
  readonly baseURL?: string;
  /** Tests only: answers requests from recorded responses. */
  readonly fetch?: typeof fetch;
}): ProviderModels {
  const client = new Anthropic({
    apiKey: options.apiKey,
    // Never the environment's: an ANTHROPIC_BASE_URL meant for another tool must not redirect
    // members' reasons.
    baseURL: options.baseURL ?? 'https://api.anthropic.com',
    timeout: options.timeoutMs ?? TIMEOUT_MS,
    maxRetries: 1,
    ...(options.fetch === undefined ? {} : { fetch: options.fetch }),
  });
  return {
    answer: async ({ model, instructions, prompt, reply }) => {
      let message;
      try {
        message = await client.messages.parse({
          model,
          max_tokens: options.maxOutputTokens ?? MAX_TOKENS,
          system: instructions,
          messages: [{ role: 'user', content: prompt }],
          // Short, playful lines: low effort keeps the wait short.
          output_config: { effort: 'low', format: zodOutputFormat(reply) },
        });
      } catch (error) {
        throw new DisclaimerWriterUnavailableError({ cause: error });
      }
      // A refusal or a cut-off answer has nothing to parse.
      if (message.stop_reason !== 'end_turn' || message.parsed_output === null) {
        throw new DisclaimerWriterUnavailableError({
          cause: new Error(`The model stopped with ${String(message.stop_reason)}`),
        });
      }
      return message.parsed_output;
    },
  };
}
