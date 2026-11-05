import type { CoachGift, GiftPiece, GiftPieceEdit, GiftRequest } from '../domain/gifts.js';
import type { MemberId } from '../domain/unlocks.js';
import { GiftPieceNotOfferedError } from '../errors.js';
import type { GiftStore } from '../ports.js';

/**
 * Gifts from a squad's coach: what a coach may give, and giving it. The coach's own tool calls
 * `give` once a coach decides to (not built yet); the module checks only that the piece is offered,
 * so who may give what to whom is the caller's job.
 */
export interface CoachGifts {
  /** The pieces coaches may give now, by id. */
  offered(): Promise<GiftPiece[]>;
  /**
   * Gives `request.piece` to `request.member` from its coach, now. Giving a piece they already
   * have keeps the first gift and answers `fresh: false`.
   */
  give(request: GiftRequest): Promise<{ gift: CoachGift; fresh: boolean }>;
  /** What `member` was given, the earliest first. */
  of(member: MemberId): Promise<CoachGift[]>;
}

/** The gift pool, for admins. */
export interface GiftsAdmin {
  pieces(): Promise<GiftPiece[]>;
  /** Adds a piece to the pool or changes whether it is offered, and answers with the pool now. */
  putPiece(edit: GiftPieceEdit): Promise<GiftPiece[]>;
}

export function createCoachGifts(deps: {
  readonly store: GiftStore;
  /** Told each new gift once it is kept; left out where nobody needs telling. */
  readonly gifted?: (member: MemberId, gift: CoachGift) => Promise<void>;
}): CoachGifts & GiftsAdmin {
  return {
    offered: async () => (await deps.store.pieces()).filter(({ offered }) => offered),

    async give({ member, piece, coach, squad }) {
      const pool = await deps.store.pieces();
      if (!pool.some(({ id, offered }) => id === piece && offered)) {
        throw new GiftPieceNotOfferedError(piece);
      }
      const given = await deps.store.give(member, { piece, coach, squad });
      if (given.fresh) await deps.gifted?.(member, given.gift);
      return given;
    },

    of: (member) => deps.store.giftsOf(member),

    pieces: () => deps.store.pieces(),

    async putPiece(edit) {
      await deps.store.putPiece(edit);
      return deps.store.pieces();
    },
  };
}
