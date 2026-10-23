import { MemberId, WeekSummaryWordsChange, type WeekSummaryWordsAdmin } from '@wildcard/check-ins';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The words of the Sunday summary (周日战报): each award's name, symbol and what a winner won it
// by, and each count's name, in Chinese and English. A change shows on the next summary anyone
// opens, with no app release and no deploy, and each one is logged with the whole new value.

interface WeekSummaryWordToolDependencies {
  readonly words: WeekSummaryWordsAdmin;
}

/** `get_week_summary_words`: the summary's words now. */
export function getWeekSummaryWords({ words }: WeekSummaryWordToolDependencies) {
  return adminTool({
    name: 'get_week_summary_words',
    title: 'Read the 战报 words',
    description:
      'Shows the words of the Sunday summary (周日战报) now: for each award its SF Symbol, its ' +
      'name and what a winner won it by (`{n}` is the number; `one` when it is 1, `other` ' +
      'otherwise), and each count’s name, in zh-Hans and en.',
    changes: false,
    input: z.strictObject({}),
    run: async () => words.current(),
  });
}

/** `change_week_summary_words`: replaces the words of some awards and counts. */
export function changeWeekSummaryWords({ words }: WeekSummaryWordToolDependencies) {
  return adminTool({
    name: 'change_week_summary_words',
    title: 'Change the 战报 words',
    description:
      'Replaces the words of the awards and counts it names, each whole (symbol, name and ' +
      'winner words for an award; both languages for a count); the rest stay as they are. The ' +
      'awards and counts themselves are rules in code, so none can be added here. Shows on the ' +
      'next summary anyone opens. Returns the words now.',
    changes: true,
    input: WeekSummaryWordsChange.refine(
      ({ awards, stats }) => Object.keys(awards ?? {}).length + Object.keys(stats ?? {}).length > 0,
      { message: 'Name at least one award or count to change' },
    ),
    run: async (change, { admin }) => words.change(change, MemberId.parse(admin)),
  });
}

export const weekSummaryWordTools = (deps: WeekSummaryWordToolDependencies) => [
  getWeekSummaryWords(deps),
  changeWeekSummaryWords(deps),
];
