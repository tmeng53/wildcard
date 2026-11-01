import { Usage, type ModelProvider } from '@openai/agents-core';
import {
  ScriptedModel,
  assistantMessage,
  functionCall,
  modelError,
} from '@openai/agents-core/testing';
import { CoachModel, type CoachTool } from '@wildcard/coach';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createOpenAICoachAgent } from './openai-coach-agent.js';

/** A provider that answers every run from one scripted model, never OpenAI. */
function scripted(model: ScriptedModel): ModelProvider {
  return { getModel: () => Promise.resolve(model) };
}

const usage = (inputTokens: number, { outputTokens = 0, cachedTokens = 0 } = {}) =>
  new Usage({
    requests: 1,
    inputTokens,
    outputTokens,
    totalTokens: inputTokens + outputTokens,
    inputTokensDetails: { cached_tokens: cachedTokens },
  });

/** A tool that records what it was called with. */
function recordingTool(calls: unknown[]): CoachTool {
  return {
    name: 'post_note',
    description: '写一句',
    parameters: z.object({ text: z.string() }),
    run: (input) => {
      calls.push(input);
      return Promise.resolve('已写上战术板。');
    },
  };
}

const request = {
  model: CoachModel.parse('openai/gpt-6-luna'),
  instructions: '你是小混。',
  task: '新的一天。',
  cacheKey: 'coach:xiaohun',
};

describe('the coach on the OpenAI Agents SDK', () => {
  it('runs the tools the model calls, and counts every request’s tokens', async () => {
    const model = new ScriptedModel([
      {
        output: [functionCall('post_note', { text: '先动起来' }, { callId: 'call-1' })],
        usage: usage(1_000, { outputTokens: 50 }),
      },
      // The second turn begins with all of the first, which OpenAI had cached.
      {
        output: [assistantMessage('写好了。')],
        usage: usage(1_200, { outputTokens: 10, cachedTokens: 1_024 }),
      },
    ]);
    const calls: unknown[] = [];
    const agent = createOpenAICoachAgent({ apiKey: 'unused', modelProvider: scripted(model) });

    const run = await agent.run({ ...request, tools: [recordingTool(calls)] });

    expect(run).toStrictEqual({
      ok: true,
      usage: { requests: 2, inputTokens: 2_200, cachedInputTokens: 1_024, outputTokens: 60 },
    });
    expect(calls).toStrictEqual([{ text: '先动起来' }]);
    // The model sees the instructions and the task, and the tool's answer on its next turn.
    expect(model.firstCall?.request.systemInstructions).toBe('你是小混。');
    expect(JSON.stringify(model.lastCall?.request.input)).toContain('已写上战术板。');
    // Nothing kept on OpenAI's side.
    expect(model.firstCall?.request.modelSettings.store).toBe(false);
    // Every request of a coach is sent to the same cache, kept a day.
    expect(model.firstCall?.request.modelSettings.promptCacheRetention).toBe('24h');
    expect(model.lastCall?.request.modelSettings.providerData).toStrictEqual({
      prompt_cache_key: 'coach:xiaohun',
    });
    model.assertComplete();
  });

  it('says a run failed, with the tokens it used until then', async () => {
    const model = new ScriptedModel([
      {
        output: [functionCall('post_note', { text: '一' }, { callId: 'call-1' })],
        usage: usage(800, { outputTokens: 20 }),
      },
      modelError(new Error('insufficient_quota')),
    ]);
    const agent = createOpenAICoachAgent({ apiKey: 'unused', modelProvider: scripted(model) });

    const run = await agent.run({ ...request, tools: [recordingTool([])] });

    expect(run).toStrictEqual({
      ok: false,
      usage: { requests: 1, inputTokens: 800, cachedInputTokens: 0, outputTokens: 20 },
      error: 'Error: insufficient_quota',
    });
  });
});
