import { z } from 'zod';

// What a coach says to a check-in shared to its squad, on that check-in's wake: one line, shown
// among the post's comments with the 教练 tag, an emoji reaction, or both. Never pushed.

/** The longest reply, in characters: as long as a member's comment; the database checks the same. */
export const REPLY_LIMIT = 100;

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
  if (text.length > limit) return `太长了：${String(text.length)} 字，最多 ${String(limit)} 字。`;
  if (/队员\d+/.test(text)) return '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。';
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
  readonly at: Date;
}
