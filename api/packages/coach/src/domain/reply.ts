import { z } from 'zod';

// What a coach says to a check-in shared to its squad, on that check-in's wake: one line, shown
// among the post's comments with the 教练 tag, an emoji reaction, or both; and its answer to
// each reply a member writes to it there, one line shown as a reply to them.

/**
 * The longest reply, in characters as `lineLength` counts them: as long as a member's comment.
 * The database holds up to twice as many, all of them half characters.
 */
export const REPLY_LIMIT = 100;

/** How the model is told a line's length is counted, after each limit it reads. */
export const HALF_WIDTH = '（英文字母、数字、空格和标点算半个字）';

/**
 * How long a line members read is, as a limit counts it: a Chinese character (or any other
 * outside ASCII, an emoji too) is one, and an ASCII letter, digit, space or mark is half, since
 * it takes about half the width on screen. So an English line gets as much room as a Chinese one
 * (Tracy, 2026-11-12), and a line of N never runs past 2N characters.
 */
export function lineLength(text: string): number {
  let length = 0;
  for (const character of text) length += (character.codePointAt(0) ?? 0) < 0x80 ? 0.5 : 1;
  return length;
}

/**
 * The emoji a coach reacts with: a short list, so its reactions read as a coach's and every
 * build's reaction row shows them.
 */
export const CoachEmoji = z.enum(['❤️', '💪', '🔥', '👏', '😂', '😮', '🏆', '🫡']);
export type CoachEmoji = z.infer<typeof CoachEmoji>;

/**
 * Why a line members read (a reply, a 战术板 line) can't be sent as it is, or `undefined` when it
 * can. The model sees members as 队员N, which members never see, so a line may not name anyone
 * that way.
 */
export function lineProblem(text: string, limit: number): string | undefined {
  if (text === '') return '这句是空的。';
  const length = Math.ceil(lineLength(text));
  if (length > limit) {
    return `太长了：${String(length)} 字${HALF_WIDTH}，最多 ${String(limit)} 字。`;
  }
  if (/队员\s*[0-9０-９]+/.test(text))
    return '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。';
  return undefined;
}

/** A coach's reply to one check-in, as members read it. */
export interface CoachReply {
  readonly checkIn: string;
  readonly coach: { readonly id: string; readonly name: string; readonly look: string };
  /** Its line, or `undefined` when it only reacted. */
  readonly text: string | undefined;
  /** Its emoji, or `undefined` when it only spoke. */
  readonly emoji: string | undefined;
  /** Whom its line @s, in the order written; empty when none. */
  readonly mentions: readonly string[];
  readonly at: Date;
}

/** A coach's answer to a member's reply to it, as members read it. */
export interface CoachAnswer {
  readonly checkIn: string;
  /** The member's reply it answers. */
  readonly comment: string;
  readonly coach: CoachReply['coach'];
  readonly text: string;
  /** Whom it @s, in the order written; empty when none. */
  readonly mentions: readonly string[];
  readonly at: Date;
}
