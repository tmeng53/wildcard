import type { CoachAgent } from '@wildcard/coach';

import { codeVerdict, judgeVerdict, type Judge, type Verdict } from './checks.js';
import type { EvalCase, EvalSettings, Expectation } from './eval-case.js';
import { runTrial, type TrialOutcome } from './harness.js';

// Runs every case a few times on the same settings and grades each trial. A case passes a trial
// when all its expectations hold; its pass rate over the trials is what changes are compared on,
// since the model doesn't answer the same way twice.

export interface TrialResult {
  readonly trial: number;
  readonly outcome: TrialOutcome;
  /** Each expectation's verdict, in the case's order; `undefined` when no judge was given. */
  readonly verdicts: readonly (Verdict | undefined)[];
  readonly pass: boolean;
}

export interface CaseResult {
  readonly id: string;
  readonly title: string;
  readonly expect: readonly Expectation[];
  readonly trials: readonly TrialResult[];
}

export interface EvalRun {
  readonly model: string;
  readonly reasoning: string;
  readonly judge: string | undefined;
  readonly cases: readonly CaseResult[];
  /** What the coach's runs cost, US dollars' millionths. */
  readonly costMicros: number;
}

export async function runEval({
  cases,
  settings,
  agent,
  trials,
  judge,
  progress = () => undefined,
}: {
  readonly cases: readonly EvalCase[];
  readonly settings: EvalSettings;
  readonly agent: CoachAgent;
  readonly trials: number;
  readonly judge?: Judge;
  readonly progress?: (line: string) => void;
}): Promise<EvalRun> {
  const results = await Promise.all(
    cases.map(async (testCase): Promise<CaseResult> => {
      const done = await Promise.all(
        Array.from({ length: trials }, async (_, index): Promise<TrialResult> => {
          // The task the wake gave the model, for the judge to read.
          let task = '';
          const outcome = await runTrial(testCase, {
            settings,
            agent: {
              run: (request) => {
                task = request.task;
                return agent.run(request);
              },
            },
          });
          const verdicts = await Promise.all(
            testCase.expect.map(async (expectation) => {
              if (outcome.error !== undefined) return { pass: false, note: outcome.error };
              const byCode = codeVerdict(expectation, outcome);
              if (byCode !== undefined) return byCode;
              if (expectation.kind !== 'judge' || judge === undefined) return undefined;
              return judgeVerdict(judge, { criterion: expectation.criterion, task, outcome });
            }),
          );
          const pass = verdicts.every((verdict) => verdict === undefined || verdict.pass);
          progress(`${testCase.id} #${String(index + 1)} ${pass ? 'pass' : 'FAIL'}`);
          return { trial: index + 1, outcome, verdicts, pass };
        }),
      );
      return { id: testCase.id, title: testCase.title, expect: testCase.expect, trials: done };
    }),
  );
  return {
    model: settings.coach.model,
    reasoning: settings.coach.reasoning,
    judge: judge?.name,
    cases: results,
    costMicros: results
      .flatMap(({ trials: each }) => each)
      .reduce((sum, { outcome }) => sum + outcome.costMicros, 0),
  };
}

/** The run as Markdown: a table of pass rates, then each failed trial's lines and why. */
export function reportOf(run: EvalRun, { at }: { readonly at: Date }): string {
  const passed = run.cases.flatMap(({ trials }) => trials).filter(({ pass }) => pass).length;
  const total = run.cases.flatMap(({ trials }) => trials).length;
  const lines = [
    `# Coach eval ${at.toISOString()}`,
    '',
    `Model ${run.model}, reasoning ${run.reasoning}, judge ${run.judge ?? 'none (judge checks skipped)'}.`,
    `Passed ${String(passed)}/${String(total)} trials. Coach cost $${(run.costMicros / 1_000_000).toFixed(4)}.`,
    '',
    '| Case | Pass | Failed checks |',
    '| --- | --- | --- |',
    ...run.cases.map(({ id, expect, trials }) => {
      const ok = trials.filter(({ pass }) => pass).length;
      const failing = expect
        .map((expectation, index) => ({
          label: labelOf(expectation),
          fails: trials.filter(({ verdicts }) => verdicts[index]?.pass === false).length,
        }))
        .filter(({ fails }) => fails > 0)
        .map(({ label, fails }) => `${label} ×${String(fails)}`);
      return `| ${id} | ${String(ok)}/${String(trials.length)} | ${failing.join('; ')} |`;
    }),
  ];
  for (const { id, expect, trials } of run.cases) {
    for (const { trial, outcome, verdicts, pass } of trials) {
      if (pass) continue;
      lines.push('', `## ${id} #${String(trial)}`, '');
      if (outcome.error !== undefined) lines.push(`- Error: ${outcome.error}`);
      if (outcome.reply !== undefined) lines.push(`- Reply: ${outcome.reply}`);
      if (outcome.answer !== undefined) lines.push(`- Answer: ${outcome.answer}`);
      lines.push(`- Tools: ${outcome.steps.map(({ tool }) => tool).join(', ') || '(none)'}`);
      expect.forEach((expectation, index) => {
        const verdict = verdicts[index];
        if (verdict?.pass === false) {
          lines.push(`- Failed ${labelOf(expectation)}: ${verdict.note ?? ''}`);
        }
      });
    }
  }
  return `${lines.join('\n')}\n`;
}

function labelOf(expectation: Expectation): string {
  switch (expectation.kind) {
    case 'tool':
      return `${expectation.called ? '' : 'no '}${expectation.tool}`;
    case 'says':
      return 'says';
    case 'avoids':
      return `avoids ${expectation.words.join('/')}`;
    case 'language':
      return expectation.language;
    case 'judge':
      return `judge「${expectation.criterion.slice(0, 24)}」`;
  }
}
