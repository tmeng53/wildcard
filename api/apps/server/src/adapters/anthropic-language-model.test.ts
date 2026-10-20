import { DisclaimerWriterUnavailableError } from '@wildcard/disclaimer-drafts';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { recordedModel, type Fixture } from '../test-kit/recorded-model.js';
import { ANTHROPIC_MODEL, createAnthropicLanguageModel } from './anthropic-language-model.js';

const Reply = z.strictObject({
  version: z.literal(1),
  outcome: z.enum(['drafts', 'selfHarm', 'unsafe']),
  drafts: z.array(z.string()),
});

function modelAnswering(...fixtures: [Fixture, ...Fixture[]]) {
  const recorded = recordedModel('anthropic', ...fixtures);
  const model = createAnthropicLanguageModel({
    apiKey: 'sk-ant-test',
    baseURL: 'http://anthropic.test',
    fetch: recorded.fetch,
  });
  const answer = () => model.answer({ instructions: 'system', prompt: 'user', reply: Reply });
  return { answer, requests: recorded.requests };
}

describe('createAnthropicLanguageModel', () => {
  it('asks Haiku for the reply’s shape and returns the parsed reply', async () => {
    const { answer, requests } = modelAnswering('drafts');
    const reply = await answer();
    expect(reply.outcome).toBe('drafts');
    expect(reply.drafts).toHaveLength(3);
    expect(requests).toHaveLength(1);
    const request = z
      .object({
        model: z.string(),
        system: z.string(),
        messages: z.array(z.object({ role: z.string(), content: z.string() })),
        output_config: z.object({
          effort: z.string(),
          format: z.object({ type: z.string(), schema: z.record(z.string(), z.unknown()) }),
        }),
      })
      .parse(requests[0]);
    expect(request.model).toBe('claude-haiku-5-5');
    expect(ANTHROPIC_MODEL).toBe('claude-haiku-5-5');
    expect(request.system).toBe('system');
    expect(request.messages).toEqual([{ role: 'user', content: 'user' }]);
    expect(request.output_config.effort).toBe('low');
    expect(request.output_config.format.type).toBe('json_schema');
    expect(request.output_config.format.schema).toMatchObject({
      type: 'object',
      required: ['version', 'outcome', 'drafts'],
      additionalProperties: false,
    });
  });

  it.each<Fixture>(['refusal', 'max-tokens'])(
    'answers %s as unavailable: there is nothing to show',
    async (fixture) => {
      await expect(modelAnswering(fixture).answer()).rejects.toBeInstanceOf(
        DisclaimerWriterUnavailableError,
      );
    },
  );

  it('retries an overloaded API once, then answers', async () => {
    const { answer, requests } = modelAnswering('overloaded', 'drafts');
    expect((await answer()).outcome).toBe('drafts');
    expect(requests).toHaveLength(2);
  });

  it('answers unavailable when the API stays down, after one retry', async () => {
    const { answer, requests } = modelAnswering('overloaded');
    await expect(answer()).rejects.toBeInstanceOf(DisclaimerWriterUnavailableError);
    expect(requests).toHaveLength(2);
  });
});
