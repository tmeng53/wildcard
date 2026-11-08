import { z } from 'zod';

import { PieceId, type MemberId } from './unlocks.js';

// Gifts from a squad's coach: pieces no store sells, which a coach may decide to give a member
// (Tracy, 2026-11-04). They are not unlocks by training: they never sit in a store, and the app
// keeps them in the member's wardrobe.

/** A coach's id, as the coaches catalog keeps it. */
export const CoachId = z.string().regex(/^[a-z][a-z0-9-]{1,39}$/);
export type CoachId = z.infer<typeof CoachId>;

/** A piece in the gift pool. `offered = false` stops new gifts of it; who has one keeps it. */
export interface GiftPiece {
  readonly id: PieceId;
  readonly offered: boolean;
  /** What the piece is, as the coach's model reads it, so it knows what it would be giving. */
  readonly description?: string;
}

/** The longest line a gift comes with, in characters; the database checks the same. */
export const GIFT_LINE_LIMIT = 60;

/** Who gave a gift: the coach on its own, or an admin in the coach's name. */
export const GivenBy = z.enum(['coach', 'admin']);
export type GivenBy = z.infer<typeof GivenBy>;

/** A piece a coach gave a member. Never taken back. */
export interface CoachGift {
  readonly piece: PieceId;
  readonly coach: CoachId;
  /** The squad the coach was coaching when it gave it. */
  readonly squad: string;
  readonly givenAt: Date;
  /** What the coach said with it; gifts from before lines have none. */
  readonly line?: string;
  readonly givenBy: GivenBy;
  /** When the member opened it (拆开), and whether they put it on then. */
  readonly opened?: { readonly at: Date; readonly worn: boolean };
}

/** A gift as the coach (or an admin in its name) asks to give it. */
export interface GiftRequest {
  readonly member: MemberId;
  readonly piece: PieceId;
  readonly coach: CoachId;
  readonly squad: string;
  readonly line: string;
  readonly givenBy: GivenBy;
  /** The admin who gave it in the coach's name. */
  readonly admin?: MemberId;
  /**
   * The start of the member's week: a member gets at most one gift a week (Tracy, 2026-11-08),
   * so a member given one since then is refused.
   */
  readonly weekStart: Date;
}

/** A piece added to the pool or changed, as an admin does it. */
export const GiftPieceEdit = z.strictObject({
  id: PieceId.describe('The piece’s id in the app’s art, such as `gift-scarf`. No store sells it.'),
  offered: z
    .boolean()
    .describe('Whether coaches may give it now; false stops new gifts, and who has one keeps it.'),
  description: z
    .string()
    .trim()
    .min(1)
    .max(200)
    .optional()
    .describe(
      'What the piece is, in Chinese, as the coach’s model reads it before giving it (what it looks like, when it fits). Left out keeps the one it has.',
    ),
});
export type GiftPieceEdit = z.infer<typeof GiftPieceEdit>;
