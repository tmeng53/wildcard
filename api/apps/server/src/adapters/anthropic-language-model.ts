import Anthropic from '@anthropic-ai/sdk';
import { zodOutputFormat } from '@anthropic-ai/sdk/helpers/zod';
import { DisclaimerWriterUnavailableError, type LanguageModel } from '@wildcard/disclaimer-drafts';

/** Claude Haiku 5.5: fast and cheap, and it won the blind test for 免责 copy (2026-10-18). */
export const ANTHROPIC_MODEL = 'claude-haiku-5-5';

/**
 * A member is waiting with the button pressed: past this, the app's dice are the better answer.
 * Counted per attempt; with one retry a request takes at most twice this.
 */
const TIMEOUT_MS = 8_000;

/** Three drafts of up to 80 characters fit in a few hundred tokens. */
const MAX_TOKENS = 1_024;

/** The language model on Anthropic's Claude API, with structured output. */
export function createAnthropicLanguageModel(options: {
  readonly apiKey: string;
  /** Tests only: where requests go, instead of Anthropic. */
  readonly baseURL?: string;
  /** Tests only: answers requests from recorded responses. */
  readonly fetch?: typeof fetch;
}): LanguageModel {
  const client = new Anthropic({
    apiKey: options.apiKey,
    // Never the environment's: an ANTHROPIC_BASE_URL meant for another tool must not redirect
    // members' reasons.
    baseURL: options.baseURL ?? 'https://api.anthropic.com',
    timeout: TIMEOUT_MS,
    maxRetries: 1,
    ...(options.fetch === undefined ? {} : { fetch: options.fetch }),
  });
  return {
    answer: async ({ instructions, prompt, reply }) => {
      let message;
      try {
        message = await client.messages.parse({
          model: ANTHROPIC_MODEL,
          max_tokens: MAX_TOKENS,
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
