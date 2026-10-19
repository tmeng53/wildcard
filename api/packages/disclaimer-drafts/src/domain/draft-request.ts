import { z } from 'zod';

// What a member asks for when they tap 「编几句」 on a 今日免责声明: the reason they typed, and
// a style. The meme library supplies this week's memes; this module only reads them.

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/** The four styles (Tracy, 2026-10-19), as the wire names them. */
export const DraftStyle = z.enum(['funny', 'unhinged', 'heroic', 'stubborn']);
export type DraftStyle = z.infer<typeof DraftStyle>;

/** Each style's name in the prompt. */
export const STYLE_NAMES: Record<DraftStyle, string> = {
  funny: '搞笑',
  unhinged: '发疯',
  heroic: '中二',
  stubborn: '嘴硬',
};

const graphemes = new Intl.Segmenter('und', { granularity: 'grapheme' });

/** Characters as people see them: a Chinese character or an emoji is one. */
export function graphemeCount(text: string): number {
  return Array.from(graphemes.segment(text)).length;
}

/** The longest reason the model is sent, in characters. A reason is a sentence, not a story. */
const REASON_MAX = 100;

/**
 * The reason as typed. Line breaks and runs of spaces become one space, so the reason stays one
 * line of the prompt and can't pose as another field.
 */
export const DraftReason = z
  .string()
  .max(REASON_MAX * 8)
  .transform((text) => text.replace(/\s+/gu, ' ').trim())
  .refine((text) => text.length > 0, { message: 'Must not be empty' })
  .refine((text) => graphemeCount(text) <= REASON_MAX, {
    message: `Must be at most ${String(REASON_MAX)} characters`,
  })
  .brand<'DraftReason'>();
export type DraftReason = z.infer<typeof DraftReason>;

/** A meme from this week's library, as the model is given it. Its approval examples never are. */
export interface PromptMeme {
  readonly phrase: string;
  readonly meaning: string;
  readonly background: string;
  readonly styles: readonly DraftStyle[];
}

/**
 * Words that mean the reason is about self-harm. A reason with one gets the care line straight
 * away, before any model is asked; the model also answers `selfHarm` for subtler ones. Everyday
 * exaggeration such as 「累得想死」 is left to the model, so a tired member still gets a joke.
 */
const SELF_HARM_WORDS = [
  '自杀',
  '自尽',
  '轻生',
  '自残',
  '割腕',
  '活不下去',
  '结束生命',
  'suicide',
  'suicidal',
  'kill myself',
  'self harm',
  'self-harm',
];

/** 「不想活」, but not 「不想活动」 (don't feel like moving), 「活跃」 or 「活泼」. */
const NOT_WANTING_TO_LIVE = /不想活(?![动跃泼])/u;

/** True when the reason plainly speaks of self-harm. */
export function mentionsSelfHarm(reason: DraftReason): boolean {
  const lower = reason.toLowerCase();
  return NOT_WANTING_TO_LIVE.test(lower) || SELF_HARM_WORDS.some((word) => lower.includes(word));
}
