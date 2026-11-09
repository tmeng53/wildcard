import { z } from 'zod';

import type { Challenge, ChallengeAnswer, ChallengeCompletion } from './challenge.js';
import type { CoachReply } from './reply.js';

// The coach page (Tracy, 2026-11-08): what the squad's coach has for a member, one card per thing,
// stacked in the order it came. Swiping a card away marks it seen, and it goes to 以前. Its lines
// to the member's check-ins and replies stay under the posts in 动态 only (Tracy, 2026-11-09).

/**
 * The kinds of card; the gift is the unlocks module's, the rest the coach's own. `challengeDone`
 * is the coach marking the member's challenge done, from their check-ins.
 */
export const CoachCardKind = z.enum(['board', 'note', 'challenge', 'challengeDone', 'gift']);
export type CoachCardKind = z.infer<typeof CoachCardKind>;

/** A card's id within its kind: a 战术板 line's day, a note's (its challenge's) id, a gift's piece. */
export const CoachCardId = z
  .string()
  .regex(/^[A-Za-z0-9_.:-]{1,64}$/)
  .meta({ description: 'The card’s id within its kind.', example: '42' });
export type CoachCardId = z.infer<typeof CoachCardId>;

/**
 * Whether `id` has the shape of a card of `kind`: a day for a 战术板 line, a piece id for a gift,
 * a row id (a positive whole number) otherwise. Only such ids are marked seen.
 */
export function isCardId(kind: CoachCardKind, id: string): boolean {
  switch (kind) {
    case 'board':
      return /^\d{4}-\d{2}-\d{2}$/u.test(id);
    case 'gift':
      return /^[a-z][a-z0-9]*(-[a-z0-9]+){1,3}$/u.test(id) && id.length <= 48;
    case 'note':
    case 'challenge':
    case 'challengeDone':
      return /^[1-9]\d{0,17}$/u.test(id);
  }
}

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
      readonly reason: string | undefined;
      readonly completion: ChallengeCompletion | undefined;
    })
  | (CardBase & {
      readonly kind: 'challengeDone';
      readonly day: string;
      readonly challenge: Challenge;
    });

/** The key a card is marked seen by. */
export function cardKey(kind: CoachCardKind, id: string): string {
  return `${kind}:${id}`;
}
