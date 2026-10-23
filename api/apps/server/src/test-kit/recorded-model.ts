import { readFileSync } from 'node:fs';

import { z } from 'zod';

// Tests only. Answers a model provider's API requests from the response bodies in ./anthropic/
// and ./openai/, so no test ever calls a provider or needs a key. Each body has the shape that
// provider documents (Anthropic's Messages API, OpenAI's Responses API), and both providers
// answer each fixture with the same words.

export type Provider = 'anthropic' | 'openai';

export type Fixture = 'drafts' | 'self-harm' | 'unsafe' | 'refusal' | 'max-tokens' | 'overloaded';

/** How each provider answers an overloaded request: both retry it. */
const OVERLOADED: Record<Provider, number> = { anthropic: 529, openai: 503 };

export interface RecordedModel {
  /** Pass to the adapter as `fetch`. */
  readonly fetch: typeof fetch;
  /** The JSON body of every request made so far. */
  readonly requests: unknown[];
}

/** A `fetch` that answers each request with the next fixture, the last one repeating. */
export function recordedModel(
  provider: Provider,
  ...fixtures: [Fixture, ...Fixture[]]
): RecordedModel {
  const requests: unknown[] = [];
  const replay: typeof fetch = async (input, init) => {
    const body = init?.body ?? (input instanceof Request ? await input.text() : undefined);
    requests.push(JSON.parse(z.string().parse(body)));
    const name = fixtures[Math.min(requests.length, fixtures.length) - 1] ?? fixtures[0];
    const text = readFileSync(new URL(`${provider}/${name}.json`, import.meta.url), 'utf8');
    return new Response(text, {
      status: name === 'overloaded' ? OVERLOADED[provider] : 200,
      headers: {
        'content-type': 'application/json',
        'request-id': `req_${name}`,
        'x-request-id': `req_${name}`,
      },
    });
  };
  return { fetch: replay, requests };
}
