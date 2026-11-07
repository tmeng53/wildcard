import type { LanguageModel } from '@wildcard/language-model';

import type { Provider } from '../model-choice.js';

// The language models the server can call, by provider: each provider's adapter answers with
// its own model names (`gpt-6-luna`). Which model a module uses is its
// settings' (in the database), named `provider/model`; the server holds each provider's key and
// sends a request to that provider with the model's name.

/**
 * A language model that sends each request to its model's provider. A provider with no key (no
 * entry in `providers`) is refused with `missing`'s error, which tells the module the AI is off.
 */
export function byProvider(
  providers: Partial<Record<Provider, LanguageModel>>,
  missing: () => Error,
): LanguageModel {
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
