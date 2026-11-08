import { z } from 'zod';

import type { Challenge, ChallengeAnswer } from './challenge.js';
import type { CoachReply } from './reply.js';

// The coach page (Tracy, 2026-11-08): everything the squad's coach said to a member, one card per
// thing, stacked in the order it came. Swiping a card away marks it seen, and it goes to 以前.

/** The kinds of card; the gift is the unlocks module's, the rest the coach's own. */
export const CoachCardKind = z.enum(['board', 'note', 'challenge', 'gift', 'reply', 'answer']);
export type CoachCardKind = z.infer<typeof CoachCardKind>;

/** A card's id within its kind: a 战术板 line's day, a note's or a reply's id, a gift's piece. */
export const CoachCardId = z
  .string()
  .regex(/^[A-Za-z0-9_.:-]{1,64}$/u)
  .meta({ description: 'The card’s id within its kind.', example: '42' });
export type CoachCardId = z.infer<typeof CoachCardId>;

/** How far back the page reaches, stack and 以前 together. */
export const CARDS_DAYS = 30;

/** How old an unseen card may be and still be in the stack; older ones are only in 以前. */
export const STACK_HOURS = 72;

interface CardBase {
  readonly id: string;
  readonly coach: CoachReply['coach'];
  readonly at: Date;
}

/** One of the coach's own cards for a member, as its store reads them. */
export type CoachOwnCard =
  | (CardBase & { readonly kind: 'board'; readonly day: string; readonly text: string })
  | (CardBase & { readonly kind: 'note'; readonly day: string; readonly text: string })
  | (CardBase & {
      readonly kind: 'challenge';
      readonly day: string;
      readonly challenge: Challenge;
      readonly answer: ChallengeAnswer | undefined;
    })
  | (CardBase & { readonly kind: 'reply'; readonly checkIn: string; readonly text: string })
  | (CardBase & {
      readonly kind: 'answer';
      readonly checkIn: string;
      readonly comment: string;
      readonly text: string;
    });

/** The key a card is marked seen by. */
export function cardKey(kind: CoachCardKind, id: string): string {
  return `${kind}:${id}`;
}
