import { readFileSync } from 'node:fs';

import { z } from 'zod';

// Tests only. Answers Claude API requests from the response bodies in ./anthropic/, so no test
// ever calls Anthropic or needs a key. Each body has the Messages API's documented shape.

export type Fixture =
  'drafts' | 'self-harm' | 'unsafe' | 'body-talk' | 'refusal' | 'max-tokens' | 'overloaded';

const STATUS: Partial<Record<Fixture, number>> = { overloaded: 529 };

export interface RecordedAnthropic {
  /** Pass to the adapter as `fetch`. */
  readonly fetch: typeof fetch;
  /** The JSON body of every request made so far. */
  readonly requests: unknown[];
}

/** A `fetch` that answers each request with the next fixture, the last one repeating. */
export function recordedAnthropic(...fixtures: [Fixture, ...Fixture[]]): RecordedAnthropic {
  const requests: unknown[] = [];
  const replay: typeof fetch = async (input, init) => {
    const body = init?.body ?? (input instanceof Request ? await input.text() : undefined);
    requests.push(JSON.parse(z.string().parse(body)));
    const name = fixtures[Math.min(requests.length, fixtures.length) - 1] ?? fixtures[0];
    const text = readFileSync(new URL(`anthropic/${name}.json`, import.meta.url), 'utf8');
    return new Response(text, {
      status: STATUS[name] ?? 200,
      headers: { 'content-type': 'application/json', 'request-id': `req_${name}` },
    });
  };
  return { fetch: replay, requests };
}
