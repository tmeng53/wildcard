import { z } from 'zod';

// The 请假条 dice: ready-made lines the app rolls when the AI can't write. Kept in the database
// and served in the public catalog, so a line changes without an app release.

const line = (language: string) => z.string().trim().min(1).max(60).describe(language);

/** One line in every language the app speaks. */
export const DiceLine = z.strictObject({
  zhHans: line('Simplified Chinese.'),
  en: line('English.'),
  zhHant: line('Traditional Chinese (Taiwan).'),
});
export type DiceLine = z.infer<typeof DiceLine>;

/** 3 to 50 lines, no two alike in any language, so the three the app rolls always differ. */
export const DiceLineList = z
  .array(DiceLine)
  .min(3)
  .max(50)
  .refine(
    (lines) =>
      (['zhHans', 'en', 'zhHant'] as const).every(
        (language) => new Set(lines.map((line) => line[language])).size === lines.length,
      ),
    { message: 'Two lines say the same thing' },
  );

/** Every line, as stored and logged. The app rolls three different ones at a time. */
export const DiceLines = z.strictObject({ version: z.literal(1), lines: DiceLineList });
export type DiceLines = z.infer<typeof DiceLines>;
