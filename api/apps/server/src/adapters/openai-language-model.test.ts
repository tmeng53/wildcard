import { DisclaimerWriterUnavailableError } from '@wildcard/disclaimer-drafts';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { recordedModel, type Fixture } from '../test-kit/recorded-model.js';
import { OPENAI_MODEL, createOpenAILanguageModel } from './openai-language-model.js';

const Reply = z.strictObject({
  version: z.literal(1),
  outcome: z.enum(['drafts', 'selfHarm', 'unsafe']),
  drafts: z.array(z.string()),
});

function modelAnswering(fixtures: [Fixture, ...Fixture[]], model?: string) {
  const recorded = recordedModel('openai', ...fixtures);
  const language = createOpenAILanguageModel({
    apiKey: 'sk-openai-test',
    ...(model === undefined ? {} : { model }),
    baseURL: 'http://openai.test',
    fetch: recorded.fetch,
  });
  const answer = () => language.answer({ instructions: 'system', prompt: 'user', reply: Reply });
  return { answer, requests: recorded.requests };
}

const Request = z.object({
  model: z.string(),
  instructions: z.string(),
  input: z.string(),
  store: z.boolean(),
  reasoning: z.object({ effort: z.string() }),
  text: z.object({
    format: z.object({
      type: z.string(),
      name: z.string(),
      strict: z.boolean(),
      schema: z.record(z.string(), z.unknown()),
    }),
  }),
});

describe('createOpenAILanguageModel', () => {
  it('asks GPT-6 Luna for the reply’s shape and returns the parsed reply', async () => {
    const { answer, requests } = modelAnswering(['drafts']);
    const reply = await answer();
    expect(reply.outcome).toBe('drafts');
    expect(reply.drafts).toHaveLength(3);
    expect(requests).toHaveLength(1);
    const request = Request.parse(requests[0]);
    expect(request.model).toBe('gpt-6-luna');
    expect(OPENAI_MODEL).toBe('gpt-6-luna');
    expect(request.instructions).toBe('system');
    expect(request.input).toBe('user');
    expect(request.store).toBe(false);
    expect(request.reasoning.effort).toBe('low');
    expect(request.text.format).toMatchObject({ type: 'json_schema', strict: true });
    expect(request.text.format.schema).toMatchObject({
      type: 'object',
      required: ['version', 'outcome', 'drafts'],
      additionalProperties: false,
    });
  });

  it('asks the model the config names', async () => {
    const { answer, requests } = modelAnswering(['drafts'], 'gpt-5.5');
    await answer();
    expect(Request.parse(requests[0]).model).toBe('gpt-5.5');
  });

  it.each<Fixture>(['refusal', 'max-tokens'])(
    'answers %s as unavailable: there is nothing to show',
    async (fixture) => {
      await expect(modelAnswering([fixture]).answer()).rejects.toBeInstanceOf(
        DisclaimerWriterUnavailableError,
      );
    },
  );

  it('retries an overloaded API once, then answers', async () => {
    const { answer, requests } = modelAnswering(['overloaded', 'drafts']);
    expect((await answer()).outcome).toBe('drafts');
    expect(requests).toHaveLength(2);
  });

  it('answers unavailable when the API stays down, after one retry', async () => {
    const { answer, requests } = modelAnswering(['overloaded']);
    await expect(answer()).rejects.toBeInstanceOf(DisclaimerWriterUnavailableError);
    expect(requests).toHaveLength(2);
  });
});
