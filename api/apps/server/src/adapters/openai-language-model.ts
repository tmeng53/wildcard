import { DisclaimerWriterUnavailableError } from '@wildcard/disclaimer-drafts';
import OpenAI from 'openai';
import { zodTextFormat } from 'openai/helpers/zod';

import type { ProviderModels } from './language-models.js';

/**
 * A member is waiting with the button pressed: past this, the app's dice are the better answer.
 * Counted per attempt; with one retry a request takes at most twice this.
 */
const TIMEOUT_MS = 8_000;

/** Three drafts of up to 80 characters fit in a few hundred tokens; the rest is for reasoning. */
const MAX_OUTPUT_TOKENS = 4_096;

/** The language model on OpenAI's Responses API, with structured output. */
export function createOpenAILanguageModel(options: {
  readonly apiKey: string;
  /**
   * How long one attempt may take, and how many tokens its answer may use (reasoning
   * included). A member waiting on drafts gets the defaults; a job writing a squad's awards
   * gets more of both.
   */
  readonly timeoutMs?: number;
  readonly maxOutputTokens?: number;
  /** Tests only: where requests go, instead of OpenAI. */
  readonly baseURL?: string;
  /** Tests only: answers requests from recorded responses. */
  readonly fetch?: typeof fetch;
}): ProviderModels {
  const client = new OpenAI({
    apiKey: options.apiKey,
    // Never the environment's: an OPENAI_BASE_URL meant for another tool must not redirect
    // members' reasons.
    baseURL: options.baseURL ?? 'https://api.openai.com/v1',
    // Nor its organization or project: the key alone says whose balance pays.
    organization: null,
    project: null,
    timeout: options.timeoutMs ?? TIMEOUT_MS,
    maxRetries: 1,
    ...(options.fetch === undefined ? {} : { fetch: options.fetch }),
  });
  return {
    answer: async ({ model, instructions, prompt, reply }) => {
      let response;
      try {
        response = await client.responses.parse({
          model,
          instructions,
          input: prompt,
          max_output_tokens: options.maxOutputTokens ?? MAX_OUTPUT_TOKENS,
          // Short, playful lines: low effort keeps the wait short.
          reasoning: { effort: 'low' },
          text: { format: zodTextFormat(reply, 'reply') },
          // Members' reasons aren't kept on OpenAI's side for later turns.
          store: false,
        });
      } catch (error) {
        throw new DisclaimerWriterUnavailableError({ cause: error });
      }
      // A refusal or a cut-off answer has nothing to parse.
      if (response.status !== 'completed' || response.output_parsed === null) {
        throw new DisclaimerWriterUnavailableError({
          cause: new Error(
            `The model stopped with ${String(response.status)} (${String(response.incomplete_details?.reason)})`,
          ),
        });
      }
      return response.output_parsed;
    },
  };
}
