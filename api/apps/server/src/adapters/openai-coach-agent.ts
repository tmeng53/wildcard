import {
  Agent,
  RunContext,
  Runner,
  tool,
  type ModelProvider,
  type Usage,
} from '@openai/agents-core';
import { OpenAIProvider } from '@openai/agents-openai';
import type { AgentRun, CoachAgent, TokenUsage } from '@wildcard/coach';
import OpenAI from 'openai';

/** How many model turns one wake may take: reading, a few edits, a line, and the end. */
const MAX_TURNS = 12;

/** One request's limit, so a stuck call can't hold a wake. */
const TIMEOUT_MS = 60_000;

/** The coach's wakes as runs of an agent on the OpenAI Agents SDK, the only code that knows it. */
export function createOpenAICoachAgent(options: {
  readonly apiKey: string;
  /** Tests only: the models runs use, instead of OpenAI's. */
  readonly modelProvider?: ModelProvider;
}): CoachAgent {
  const modelProvider =
    options.modelProvider ??
    new OpenAIProvider({
      openAIClient: new OpenAI({
        apiKey: options.apiKey,
        // Never the environment's: an OPENAI_BASE_URL meant for another tool must not redirect
        // members' words, nor its organization or project: the key alone says whose balance pays.
        baseURL: 'https://api.openai.com/v1',
        organization: null,
        project: null,
        timeout: TIMEOUT_MS,
        maxRetries: 1,
      }),
    });
  // Tracing would send members' words to OpenAI's traces dashboard as well.
  const runner = new Runner({ modelProvider, tracingDisabled: true });
  return {
    async run({ model, instructions, task, tools }): Promise<AgentRun> {
      const agent = new Agent({
        name: 'coach',
        instructions,
        model: model.slice('openai/'.length),
        // Members' words aren't kept on OpenAI's side for later turns.
        modelSettings: { store: false },
        tools: tools.map((each) =>
          tool({
            name: each.name,
            description: each.description,
            parameters: each.parameters,
            execute: (input) => each.run(input),
          }),
        ),
      });
      // Ours, so what the run used is still here when it fails part way: those tokens count too.
      const context = new RunContext();
      try {
        await runner.run(agent, task, { context, maxTurns: MAX_TURNS });
        return { ok: true, usage: tokensOf(context.usage) };
      } catch (error) {
        return {
          ok: false,
          usage: tokensOf(context.usage),
          error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
        };
      }
    },
  };
}

function tokensOf(usage: Usage): TokenUsage {
  return {
    requests: usage.requests,
    inputTokens: usage.inputTokens,
    outputTokens: usage.outputTokens,
  };
}
