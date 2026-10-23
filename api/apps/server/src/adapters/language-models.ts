import type { z } from 'zod';

import type { Provider } from '../model-choice.js';

// The language models the server can call, by provider. Which model a module uses is its
// settings' (in the database), named `provider/model`; the server holds each provider's key and
// sends a request to that provider with the model's name.

/** One request to a model, in the shape both AI modules ask in. */
interface ModelRequest<Reply> {
  readonly model: string;
  readonly instructions: string;
  readonly prompt: string;
  readonly reply: z.ZodType<Reply>;
}

/** A provider's models, each called by its own name (`gpt-6-luna`). */
export interface ProviderModels {
  answer<Reply>(request: ModelRequest<Reply>): Promise<Reply>;
}

/**
 * A language model that sends each request to its model's provider. A provider with no key (no
 * entry in `providers`) is refused with `missing`'s error, which tells the module the AI is off.
 */
export function byProvider(
  providers: Partial<Record<Provider, ProviderModels>>,
  missing: () => Error,
): { answer<Reply>(request: ModelRequest<Reply>): Promise<Reply> } {
  return {
    answer: (request) => {
      const [provider = '', name = ''] = request.model.split('/', 2);
      const models =
        provider === 'openai' || provider === 'anthropic' ? providers[provider] : undefined;
      if (models === undefined) return Promise.reject(missing());
      return models.answer({ ...request, model: name });
    },
  };
}
