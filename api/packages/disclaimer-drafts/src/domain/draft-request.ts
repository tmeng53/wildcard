import type { DisclaimerStyle } from '@wildcard/disclaimer-styles';
import { typedText } from '@wildcard/typed-text';
import { z } from 'zod';

// What a member asks for when they tap 「编几句」 on a 请假条: the reason they typed, and
// a style. The meme library supplies this week's memes; this module only reads them.

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/** Each style's name in the prompt. */
export const STYLE_NAMES: Record<DisclaimerStyle, string> = {
  funny: '搞笑',
  unhinged: '发疯',
  heroic: '中二',
  stubborn: '嘴硬',
};

/** The longest reason the model is sent, in characters. A reason is a sentence, not a story. */
const REASON_MAX = 100;

/**
 * The reason as typed. Line breaks and runs of spaces become one space first, so the reason stays
 * one line of the prompt and can't pose as another field; then it follows the rules for typed text.
 */
export const DraftReason = z
  .string()
  .max(REASON_MAX * 8)
  .transform((text) => text.replace(/\s+/gu, ' '))
  .pipe(typedText({ max: REASON_MAX, oneLine: true, description: 'The reason as typed.' }))
  .brand<'DraftReason'>();
export type DraftReason = z.infer<typeof DraftReason>;

/** A meme from this week's library, as the model is given it. Its approval examples never are. */
export interface PromptMeme {
  readonly phrase: string;
  readonly meaning: string;
  readonly background: string;
  readonly styles: readonly DisclaimerStyle[];
}
