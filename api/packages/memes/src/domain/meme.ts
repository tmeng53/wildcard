import { DisclaimerStyle } from '@wildcard/disclaimer-styles';
import { typedText } from '@wildcard/typed-text';
import { z } from 'zod';

// A meme in the library: a phrase trending among Chinese speakers (or in North American
// Chinese work life), with enough background that the AI writing a 今日免责声明 knows what it
// means and how people use it. The example lines Tracy reads when she approves a meme stay out
// of the library on purpose (Tracy, 2026-10-19): the AI would copy them.

export const MemeId = z.uuid().brand<'MemeId'>();
export type MemeId = z.infer<typeof MemeId>;

/** The meme itself, e.g. 「city不city」. */
export const MemePhrase = typedText({ max: 30, oneLine: false, description: 'The meme itself.' });
export type MemePhrase = z.infer<typeof MemePhrase>;

/** A meme's text, counted in characters as people see them. */
const Text = (max: number, description: string) => typedText({ max, oneLine: false, description });

// The fields kept in `memes.payload`.
const memeFields = {
  /** Where it came from and how it spread, in 2 or 3 sentences. */
  background: Text(300, 'Where it came from and how it spread.'),
  /** What it means. */
  meaning: Text(120, 'What it means.'),
  styles: z
    .array(DisclaimerStyle)
    .min(1)
    .max(4)
    .refine((styles) => new Set(styles).size === styles.length, {
      message: 'Must not list a style twice',
    }),
  /** Where it trends, e.g. 小红书. */
  source: Text(60, 'Where it trends.'),
};

/** A meme Tracy approved, as it is handed to the library. */
export const MemeDraft = z.strictObject({ phrase: MemePhrase, ...memeFields });
export type MemeDraft = z.infer<typeof MemeDraft>;

// One version so far. Until real users arrive, a change to the shape edits version 1.
const StoredMemeV1 = z.strictObject({ version: z.literal(1), ...memeFields });
/** What `memes.payload` holds. */
export const StoredMeme = z.discriminatedUnion('version', [StoredMemeV1]);
export type StoredMeme = z.infer<typeof StoredMeme>;

/** A meme in the library. */
export interface MemeRecord extends MemeDraft {
  readonly id: MemeId;
  readonly approvedAt: Date;
}

/** The stored JSON for a draft. */
export function storedPayload(meme: MemeDraft): StoredMeme {
  const { background, meaning, styles, source } = meme;
  return { version: 1, background, meaning, styles, source };
}

/** A meme is used for 4 weeks after it is approved (Tracy, 2026-10-19), then left out. */
const USED_FOR_MS = 28 * 86_400_000;

/** The earliest approval still in use at `now`. */
export function inUseSince(now: Date): Date {
  return new Date(now.getTime() - USED_FOR_MS);
}
