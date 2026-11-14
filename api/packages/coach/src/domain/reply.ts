import { z } from 'zod';

import { lengthProblem, type LineKind } from './line-limits.js';

// What a coach says to a check-in shared to its squad, on that check-in's wake: one line, shown
// among the post's comments with the 教练 tag, an emoji reaction, or both; and its answer to
// each reply a member writes to it there, one line shown as a reply to them.

/**
 * The emoji a coach reacts with: a short list, so its reactions read as a coach's and every
 * build's reaction row shows them.
 */
export const CoachEmoji = z.enum(['❤️', '💪', '🔥', '👏', '😂', '😮', '🏆', '🫡']);
export type CoachEmoji = z.infer<typeof CoachEmoji>;

/**
 * Why a line members read (a reply, a 战术板 line, a letter) can't be sent as it is, or
 * `undefined` when it can: it must fit its kind's limit in its language, and may not call anyone
 * 队员N, the stand-in name members never see.
 */
export function lineProblem(text: string, kind: LineKind): string | undefined {
  return lineProblemAmong(text, { kind, names: [] });
}

/** The same, in a squad whose names a line may say whatever they hold (a 稳哥 is still @'d). */
export function lineProblemAmong(
  text: string,
  { kind, names }: { readonly kind: LineKind; readonly names: readonly string[] },
): string | undefined {
  if (text === '') return '这句是空的。';
  const tooLong = lengthProblem(text, kind);
  if (tooLong !== undefined) return tooLong;
  if (/队员\s*[0-9０-９]+/.test(text))
    return '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。';
  // No coach says it (Tracy, 2026-11-10): held here, so no prompt has to forbid it.
  if (/[稳穩]/.test(names.reduce((rest, name) => rest.replaceAll(name, ''), text)))
    return '这句里有「稳」字，教练都不说这个字，换个说法。';
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
