import { z } from 'zod';

import { AwardKind, StatKind } from './week-summary.js';

// The words of the Sunday summary (周日战报), kept in the database so they change with no app
// release and no deploy: each award's name, symbol and what a winner won it by, and each
// count's name, in every language the summary is written in. The awards and counts themselves
// are rules in code (week-summary.ts); every kind must have its words.

/** The languages the summary is written in; Chinese first, Traditional Chinese in Taiwan's words. */
export const Language = z.enum(['zh-Hans', 'en', 'zh-Hant']);
export type Language = z.infer<typeof Language>;

const Text = z.string().trim().min(1).max(60);

/** One phrase in each language, as an admin writes it. */
const Phrase = z.strictObject({ 'zh-Hans': Text, en: Text, 'zh-Hant': Text });

/**
 * One phrase as it is stored: words saved before Traditional Chinese came have none, and read
 * as Simplified Chinese there until an admin gives them theirs (`inLanguage`). Not filled by a
 * migration, since the deploy migrates before the new server serves and the old one refuses a
 * key it doesn't know.
 */
const StoredPhrase = Phrase.partial({ 'zh-Hant': true });

/** A count in words: `{n}` stands for the number; `one` when it is 1, `other` otherwise. */
const Counted = z.strictObject({
  one: Text.includes('{n}'),
  other: Text.includes('{n}'),
});

const awardWords = <P extends z.ZodType, C extends z.ZodType>(phrase: P, winner: C) =>
  z.strictObject({
    /** An SF Symbol name the app shows next to the award. */
    symbol: z
      .string()
      .regex(/^[a-z0-9]+(\.[a-z0-9]+)*$/)
      .max(80),
    title: phrase,
    /** What a winner won it by, from the award's value. */
    winner,
  });

const WinnerWords = z.strictObject({ 'zh-Hans': Counted, en: Counted, 'zh-Hant': Counted });
const AwardWords = awardWords(Phrase, WinnerWords);
const StoredAwardWords = awardWords(StoredPhrase, WinnerWords.partial({ 'zh-Hant': true }));

export const WeekSummaryWords = z.strictObject({
  version: z.literal(1),
  awards: z.record(AwardKind, StoredAwardWords),
  stats: z.record(StatKind, StoredPhrase),
});
export type WeekSummaryWords = z.infer<typeof WeekSummaryWords>;

/** What an admin changes: the awards and counts it names, each replaced whole; the rest stay. */
export const WeekSummaryWordsChange = z.strictObject({
  awards: z.partialRecord(AwardKind, AwardWords).optional(),
  stats: z.partialRecord(StatKind, Phrase).optional(),
});
export type WeekSummaryWordsChange = z.infer<typeof WeekSummaryWordsChange>;

/** A phrase in `language`, in Simplified Chinese where it has no Traditional Chinese yet. */
export function inLanguage<T>(
  phrase: { readonly 'zh-Hans': T; readonly en: T; readonly 'zh-Hant'?: T | undefined },
  language: Language,
): T {
  return phrase[language] ?? phrase['zh-Hans'];
}

/** What a winner of `kind` won it by, in words. */
export function winnerText(
  words: WeekSummaryWords,
  winner: { readonly kind: AwardKind; readonly value: number; readonly language: Language },
): string {
  const counted = inLanguage(words.awards[winner.kind].winner, winner.language);
  return (winner.value === 1 ? counted.one : counted.other).replaceAll('{n}', String(winner.value));
}
