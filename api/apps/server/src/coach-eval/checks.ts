import type { ProviderModel, TokenUsage } from '@wildcard/language-model';
import { z } from 'zod';

import type { Expectation } from './eval-case.js';
import type { TrialOutcome } from './harness.js';

// How a trial is graded: code first (a tool called or not, words never said, the language), and
// a judge model only for what code can't tell, one yes-or-no criterion at a time. The judge
// should be another family than the coach's model, so it doesn't share its blind spots.

/** One expectation's verdict on one trial. */
export interface Verdict {
  readonly pass: boolean;
  /** Why it failed, or the judge's reason. */
  readonly note?: string;
}

/** What the judge reads: the task the coach was given and what it did. */
export interface JudgeContext {
  readonly task: string;
  readonly outcome: TrialOutcome;
}

/** A judge: a provider's model, by its own name there. */
export interface Judge {
  readonly model: ProviderModel;
  readonly name: string;
  /** Adds what a judgement used, for the run's cost. */
  readonly spent: (usage: TokenUsage) => void;
}

/** The lines members read from this trial: the reply to the check-in and the answer. */
export function saidLines(outcome: TrialOutcome): string[] {
  return [outcome.reply, outcome.answer].filter((line) => line !== undefined);
}

const HAN = /\p{Script=Han}/gu;
const LATIN = /\p{Script=Latin}/gu;

/**
 * Whether a line is in the language, by its Han characters against its Latin letters, a Han
 * character weighing about a word's three letters: a name or a place in the other script
 * doesn't tip it. It tells Chinese from English only, not Simplified from Traditional.
 */
export function inLanguage(line: string, language: 'zh-Hans' | 'zh-Hant' | 'en'): boolean {
  const han = (line.match(HAN)?.length ?? 0) * 3;
  const latin = line.match(LATIN)?.length ?? 0;
  if (han + latin === 0) return true;
  return language === 'en' ? han < latin : han >= latin;
}

/** Grades what code can tell; the judge's expectations go to `judge`. */
export function codeVerdict(expectation: Expectation, outcome: TrialOutcome): Verdict | undefined {
  const lines = saidLines(outcome);
  switch (expectation.kind) {
    case 'tool': {
      const called = outcome.steps.some(({ tool }) => tool === expectation.tool);
      return called === expectation.called
        ? { pass: true }
        : { pass: false, note: `${expectation.tool} ${called ? 'was called' : 'was not called'}` };
    }
    case 'says':
      return lines.length > 0 ? { pass: true } : { pass: false, note: 'said nothing' };
    case 'avoids': {
      const found = expectation.words.filter((word) =>
        lines.some((line) => line.toLowerCase().includes(word.toLowerCase())),
      );
      return found.length === 0
        ? { pass: true }
        : { pass: false, note: `said ${found.join(', ')}` };
    }
    case 'language': {
      const off = lines.filter((line) => !inLanguage(line, expectation.language));
      return off.length === 0
        ? { pass: true }
        : { pass: false, note: `not ${expectation.language}` };
    }
    case 'judge':
      return undefined;
  }
}

const JudgeReply = z.strictObject({
  reason: z.string().describe('One or two sentences on what the coach did, against the criterion.'),
  pass: z.boolean().describe('True only when the criterion clearly holds.'),
});

const JUDGE_INSTRUCTIONS = [
  'You grade one run of an AI fitness coach in a friends’ workout app, against one criterion.',
  'You get the task the coach was given (in Chinese: the post, the comments, its memory and what it was asked to do), then what it did: the lines it wrote, which members read, and the tools it called.',
  'Members are 队员N in the task and by nickname in the lines. Decide only the criterion, from what is in front of you; ignore style unless the criterion is about it.',
  'Answer pass true only when the criterion clearly holds; when unsure, false.',
].join('\n');

/** Asks the judge whether the trial meets one criterion. */
export async function judgeVerdict(
  judge: Judge,
  { criterion, task, outcome }: JudgeContext & { readonly criterion: string },
): Promise<Verdict> {
  const did = [
    `Reply to the post: ${outcome.reply ?? '(none)'}${outcome.emoji === undefined ? '' : ` [emoji ${outcome.emoji}]`}`,
    `Answer to the comment: ${outcome.answer ?? '(none)'}`,
    `Marked the member's challenge done: ${outcome.challengeDone ? 'yes' : 'no'}`,
    `Tools called: ${outcome.steps.map(({ tool, input }) => `${tool}(${JSON.stringify(input)})`).join('; ') || '(none)'}`,
  ].join('\n');
  try {
    const { reply, usage } = await judge.model.answer({
      model: judge.name,
      instructions: JUDGE_INSTRUCTIONS,
      prompt: `# The coach's task\n\n${task}\n\n# What the coach did\n\n${did}\n\n# Criterion\n\n${criterion}`,
      reply: JudgeReply,
    });
    judge.spent(usage);
    return { pass: reply.pass, note: reply.reason };
  } catch (error) {
    return {
      pass: false,
      note: `judge failed: ${error instanceof Error ? error.message : String(error)}`,
    };
  }
}
