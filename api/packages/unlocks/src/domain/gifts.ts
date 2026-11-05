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
}

/** A piece a coach gave a member. Never taken back. */
export interface CoachGift {
  readonly piece: PieceId;
  readonly coach: CoachId;
  /** The squad the coach was coaching when it gave it. */
  readonly squad: string;
  readonly givenAt: Date;
}

/** A gift as the coach (or the code acting for it) asks to give it. */
export interface GiftRequest {
  readonly member: MemberId;
  readonly piece: PieceId;
  readonly coach: CoachId;
  readonly squad: string;
}

/** A piece added to the pool or changed, as an admin does it. */
export const GiftPieceEdit = z.strictObject({
  id: PieceId.describe('The piece’s id in the app’s art, such as `gift-scarf`. No store sells it.'),
  offered: z
    .boolean()
    .describe('Whether coaches may give it now; false stops new gifts, and who has one keeps it.'),
});
export type GiftPieceEdit = z.infer<typeof GiftPieceEdit>;
