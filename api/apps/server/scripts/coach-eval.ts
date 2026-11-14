// The coach's offline eval: runs every case in a folder through the coach's real wake code on
// a model and setting, a few trials each, and writes a pass-rate report next to the cases.
//
//   OPENAI_API_KEY=… pnpm --dir api coach-eval --cases ../wildcard-feedback/coach-evals \
//     [--model openai/gpt-6-luna] [--reasoning medium] [--trials 3] [--only id,id] \
//     [--judge anthropic/claude-sonnet-5-5]   (needs ANTHROPIC_API_KEY)
//   pnpm --dir api coach-eval --cases … --dry   checks the cases and prints each task, no model
//
// Without --model or --reasoning, the settings file's (the live ones when it was taken). Spends
// the provider's money: run it by hand, never in CI.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';

import { CoachModel, CoachSettings } from '@wildcard/coach';
import type { ProviderModel, TokenUsage } from '@wildcard/language-model';

import { createAnthropicLanguageModel } from '../src/adapters/anthropic-language-model.js';
import { createOpenAICoachAgent } from '../src/adapters/openai-coach-agent.js';
import { createOpenAILanguageModel } from '../src/adapters/openai-language-model.js';
import type { Judge } from '../src/coach-eval/checks.js';
import { readCases } from '../src/coach-eval/case-files.js';
import { EvalSettings } from '../src/coach-eval/eval-case.js';
import { runTrial } from '../src/coach-eval/harness.js';
import { reportOf, runEval } from '../src/coach-eval/run-eval.js';

const { values } = parseArgs({
  options: {
    cases: { type: 'string', default: process.env.COACH_EVAL_DIR },
    settings: { type: 'string' },
    model: { type: 'string' },
    reasoning: { type: 'string' },
    trials: { type: 'string', default: '3' },
    only: { type: 'string' },
    judge: { type: 'string' },
    // Checks the cases and prints each one's task, asking no model.
    dry: { type: 'boolean', default: false },
  },
});

const folder = values.cases;
if (folder === undefined) throw new Error('Name the cases folder: --cases <dir>');
const openAIKey = process.env.OPENAI_API_KEY ?? '';
if (openAIKey === '' && !values.dry) throw new Error('OPENAI_API_KEY is needed to run the coach');

const stored = EvalSettings.parse(
  JSON.parse(readFileSync(values.settings ?? join(folder, 'settings.json'), 'utf8')),
);
const settings: EvalSettings = {
  ...stored,
  coach: CoachSettings.parse({
    ...stored.coach,
    ...(values.model === undefined ? {} : { model: CoachModel.parse(values.model) }),
    ...(values.reasoning === undefined ? {} : { reasoning: values.reasoning }),
  }),
};
const cases = readCases(folder, values.only?.split(','));
if (cases.length === 0) throw new Error('No cases to run');

if (values.dry) {
  for (const testCase of cases) {
    const outcome = await runTrial(testCase, {
      settings,
      agent: {
        run: ({ task }) => {
          process.stdout.write(`\n===== ${testCase.id} =====\n${task}\n`);
          return Promise.resolve({
            ok: true,
            usage: { requests: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 },
          });
        },
      },
    });
    if (outcome.error !== undefined) process.stdout.write(`${testCase.id}: ${outcome.error}\n`);
  }
  process.exit(0);
}

let judgeUsage: TokenUsage = { requests: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 };
const judge = values.judge === undefined ? undefined : judgeOf(values.judge);

const at = new Date();
const run = await runEval({
  cases,
  settings,
  agent: createOpenAICoachAgent({ apiKey: openAIKey }),
  trials: Number(values.trials),
  ...(judge === undefined ? {} : { judge }),
  progress: (line) => process.stderr.write(`${line}\n`),
});
const report = reportOf(run, { at });
const name = `${at.toISOString().slice(0, 19).replace(/[:T]/g, '-')}-${run.model.replace('/', '-')}-${run.reasoning}`;
mkdirSync(join(folder, 'results'), { recursive: true });
writeFileSync(join(folder, 'results', `${name}.md`), report);
writeFileSync(join(folder, 'results', `${name}.json`), `${JSON.stringify(run, null, 2)}\n`);
process.stdout.write(report);
if (judge !== undefined) {
  process.stdout.write(
    `Judge tokens: ${String(judgeUsage.inputTokens)} in, ${String(judgeUsage.outputTokens)} out.\n`,
  );
}

function judgeOf(named: string): Judge {
  const [provider, model] = named.split('/', 2);
  if (model === undefined) throw new Error('Name the judge as provider/model');
  const spent = (usage: TokenUsage) => {
    judgeUsage = {
      requests: judgeUsage.requests + usage.requests,
      inputTokens: judgeUsage.inputTokens + usage.inputTokens,
      cachedInputTokens: judgeUsage.cachedInputTokens + usage.cachedInputTokens,
      outputTokens: judgeUsage.outputTokens + usage.outputTokens,
    };
  };
  const keyed = (key: string | undefined, make: (apiKey: string) => ProviderModel) => {
    if (key === undefined) throw new Error(`The ${provider ?? ''} judge needs its API key`);
    return make(key);
  };
  const options = { timeoutMs: 60_000, maxOutputTokens: 4_096 };
  const providerModel =
    provider === 'anthropic'
      ? keyed(process.env.ANTHROPIC_API_KEY, (apiKey) =>
          createAnthropicLanguageModel({ apiKey, ...options }),
        )
      : provider === 'openai'
        ? keyed(openAIKey, (apiKey) => createOpenAILanguageModel({ apiKey, ...options }))
        : undefined;
  if (providerModel === undefined) throw new Error(`No judge provider ${provider ?? ''}`);
  return { model: providerModel, name: model, spent };
}
