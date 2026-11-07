import { z } from 'zod';

// The app's copy put over the words its String Catalog ships with: an admin changes a line the
// app shows (a button, a title, a push) by its catalog key, and phones show the new words from
// their next launch after reading the catalog, with no app release. A key nothing was put for
// keeps the build's own words.

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/**
 * Each argument a format string takes, by its 1-based position: `%lld`, `%@`, `%lf` as Swift
 * writes an interpolation into a catalog key, or `%2$@` with an explicit position. `%%` takes
 * none. Two strings fill the same way when these are equal.
 */
export function formatArguments(text: string): Map<number, string> {
  const found = new Map<number, string>();
  let next = 1;
  for (const [, position, conversion] of text.matchAll(
    /%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?((?:hh|h|ll|l|q|z|t|j|L)?[@dDiuUxXoOfFeEgGcCsSpaA]|%)/g,
  )) {
    if (conversion === '%' || conversion === undefined) continue;
    const at = position === undefined ? next++ : Number(position);
    found.set(at, conversion);
  }
  return found;
}

/** Whether `words` take exactly the arguments `key` takes, so the app can fill them safely. */
export function fillsLike(key: string, words: string): boolean {
  const want = formatArguments(key);
  const have = formatArguments(words);
  return (
    want.size === have.size && [...want].every(([at, conversion]) => have.get(at) === conversion)
  );
}

/** A String Catalog key, as the app's catalog has it: its Simplified Chinese source line. */
export const CopyKey = z
  .string()
  .min(1)
  .max(500)
  .describe(
    'The line’s key in the app’s String Catalog: its Simplified Chinese source, placeholders ' +
      'included (`还有 %lld 次开门`).',
  );

const line = (language: string) => z.string().min(1).max(500).describe(language);

/** A line's words in the languages it changes in; a language left out keeps the build's words. */
export const CopyWords = z
  .strictObject({
    zhHans: line('Simplified Chinese.').optional(),
    en: line('English.').optional(),
    zhHant: line('Traditional Chinese (Taiwan).').optional(),
  })
  .refine((words) => Object.keys(words).length > 0, {
    message: 'Give the words in one language at least',
  });
export type CopyWords = z.infer<typeof CopyWords>;

/** Every line put, by key; no more than this, a bound on the catalog's size. */
export const COPY_LIMIT = 2000;

export const CopyEntries = z
  .record(CopyKey, CopyWords)
  .refine((entries) => Object.keys(entries).length <= COPY_LIMIT, {
    message: `At most ${String(COPY_LIMIT)} lines`,
  })
  .superRefine((entries, context) => {
    for (const [key, words] of Object.entries(entries)) {
      for (const [language, text] of Object.entries(words)) {
        if (!fillsLike(key, text)) {
          context.addIssue({
            code: 'custom',
            path: [key, language],
            message: 'Keep the key’s placeholders (%lld, %@, …), the same kinds in the same order',
          });
        }
      }
    }
  });

/** The copy put, whole, as stored and logged. */
export const AppCopy = z.strictObject({ version: z.literal(1), entries: CopyEntries });
export type AppCopy = z.infer<typeof AppCopy>;

/** What an admin changes: lines to put (each replacing its key's words) and keys to take back. */
export const AppCopyChange = z.strictObject({
  put: z
    .record(CopyKey, CopyWords)
    .optional()
    .describe('Lines to put, by key; each replaces whatever its key had.'),
  takeBack: z
    .array(CopyKey)
    .max(COPY_LIMIT)
    .optional()
    .describe('Keys to take back to the build’s own words.'),
});
export type AppCopyChange = z.infer<typeof AppCopyChange>;

/** `copy` with `change` applied: the lines put stand over the old ones, the keys taken back go. */
export function applyChange(copy: AppCopy, change: AppCopyChange): AppCopy {
  const takenBack = new Set(change.takeBack);
  const entries = Object.fromEntries(
    Object.entries({ ...copy.entries, ...change.put }).filter(([key]) => !takenBack.has(key)),
  );
  return AppCopy.parse({ version: 1, entries });
}
