import { z } from 'zod';

import { AwardKind, StatKind } from './week-summary.js';

// The words of the Sunday summary (周日战报), kept in the database so they change with no app
// release and no deploy: each award's name, symbol and what a winner won it by, and each
// count's name, in every language the summary is written in. The awards and counts themselves
// are rules in code (week-summary.ts); every kind must have its words.

/** The languages the summary is written in; Chinese first. */
export const Language = z.enum(['zh-Hans', 'en']);
export type Language = z.infer<typeof Language>;

const Text = z.string().trim().min(1).max(60);

/** One phrase in each language. */
const Phrase = z.strictObject({ 'zh-Hans': Text, en: Text });

/** A count in words: `{n}` stands for the number; `one` when it is 1, `other` otherwise. */
const Counted = z.strictObject({
  one: Text.includes('{n}'),
  other: Text.includes('{n}'),
});

const AwardWords = z.strictObject({
  /** An SF Symbol name the app shows next to the award. */
  symbol: z
    .string()
    .regex(/^[a-z0-9]+(\.[a-z0-9]+)*$/)
    .max(80),
  title: Phrase,
  /** What a winner won it by, from the award's value. */
  winner: z.strictObject({ 'zh-Hans': Counted, en: Counted }),
});

export const WeekSummaryWords = z.strictObject({
  version: z.literal(1),
  awards: z.record(AwardKind, AwardWords),
  stats: z.record(StatKind, Phrase),
});
export type WeekSummaryWords = z.infer<typeof WeekSummaryWords>;

/** What an admin changes: the awards and counts it names, each replaced whole; the rest stay. */
export const WeekSummaryWordsChange = z.strictObject({
  awards: z.partialRecord(AwardKind, AwardWords).optional(),
  stats: z.partialRecord(StatKind, Phrase).optional(),
});
export type WeekSummaryWordsChange = z.infer<typeof WeekSummaryWordsChange>;

/** What a winner of `kind` won it by, in words. */
export function winnerText(
  words: WeekSummaryWords,
  winner: { readonly kind: AwardKind; readonly value: number; readonly language: Language },
): string {
  const counted = words.awards[winner.kind].winner[winner.language];
  return (winner.value === 1 ? counted.one : counted.other).replaceAll('{n}', String(winner.value));
}
