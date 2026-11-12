import { describe, expect, it } from 'vitest';

import { costMicros } from './usage.js';

describe('costMicros', () => {
  it('counts tokens at the model’s prices, cached input at its own, rounded up', () => {
    const price = {
      inputMicrosPerMillion: 100_000,
      cachedInputMicrosPerMillion: 10_000,
      outputMicrosPerMillion: 500_000,
    };
    // 2,000 uncached in at $0.10, 10,000 cached at $0.01, 800 out at $0.50 a million.
    expect(
      costMicros(
        { requests: 3, inputTokens: 12_000, cachedInputTokens: 10_000, outputTokens: 800 },
        price,
      ),
    ).toBe(200 + 100 + 400);
    // Nothing cached: every input token at the full price.
    expect(
      costMicros(
        { requests: 3, inputTokens: 12_000, cachedInputTokens: 0, outputTokens: 800 },
        price,
      ),
    ).toBe(1_200 + 400);
    // A part of a millionth is a whole one.
    expect(
      costMicros(
        { requests: 1, inputTokens: 1, cachedInputTokens: 0, outputTokens: 0 },
        { inputMicrosPerMillion: 1, cachedInputMicrosPerMillion: 0, outputMicrosPerMillion: 0 },
      ),
    ).toBe(1);
    // More cached than sent counts no more than was sent.
    expect(
      costMicros(
        { requests: 1, inputTokens: 1_000_000, cachedInputTokens: 2_000_000, outputTokens: 0 },
        price,
      ),
    ).toBe(10_000);
  });
});
