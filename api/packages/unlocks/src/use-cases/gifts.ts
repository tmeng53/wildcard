import type { CoachGift, GiftPiece, GiftPieceEdit, GiftRequest } from '../domain/gifts.js';
import type { MemberId, PieceId } from '../domain/unlocks.js';
import {
  GiftAlreadyOwnedError,
  GiftNotGivenError,
  GiftPieceNotOfferedError,
  GiftWeeklyLimitError,
} from '../errors.js';
import type { GiftStore } from '../ports.js';

/**
 * Gifts from a squad's coach: what a coach may give, and giving it. The rules every gift keeps
 * are here, whoever gives it (the coach's own tool or an admin in its name): the piece is
 * offered, the member hasn't got it, and they got no gift since their week began (one a week at
 * most; Tracy, 2026-11-08). Whether the member may get gifts at all (their AI consent, their
 * squad) is the caller's to check.
 */
export interface CoachGifts {
  /** The pieces coaches may give now, by id. */
  offered(): Promise<GiftPiece[]>;
  /** Gives `request.piece` to `request.member` from its coach, now. */
  give(request: GiftRequest): Promise<CoachGift>;
  /** What `member` was given, the earliest first. */
  of(member: MemberId): Promise<CoachGift[]>;
  /**
   * Keeps that `member` opened their gift of `piece` (拆开) and whether they put it on then.
   * Opening it again keeps the first; answers with the gift as it stands.
   */
  open(member: MemberId, piece: PieceId, worn: boolean): Promise<CoachGift>;
}

/** The gift pool, for admins. */
export interface GiftsAdmin {
  pieces(): Promise<GiftPiece[]>;
  /** Adds a piece to the pool or changes it, and answers with the pool now. */
  putPiece(edit: GiftPieceEdit): Promise<GiftPiece[]>;
}

export function createCoachGifts(deps: {
  readonly store: GiftStore;
  /** Told each new gift once it is kept; left out where nobody needs telling. */
  readonly gifted?: (member: MemberId, gift: CoachGift) => Promise<void>;
}): CoachGifts & GiftsAdmin {
  return {
    offered: async () => (await deps.store.pieces()).filter(({ offered }) => offered),

    async give({ member, piece, coach, squad, line, givenBy, admin, weekStart }) {
      const pool = await deps.store.pieces();
      if (!pool.some(({ id, offered }) => id === piece && offered)) {
        throw new GiftPieceNotOfferedError(piece);
      }
      const had = await deps.store.giftsOf(member);
      if (had.some((gift) => gift.piece === piece)) throw new GiftAlreadyOwnedError(piece);
      const thisWeek = had.filter(({ givenAt }) => givenAt >= weekStart).at(-1);
      if (thisWeek !== undefined) throw new GiftWeeklyLimitError(thisWeek.givenAt);
      const gift = await deps.store.give(member, {
        piece,
        coach,
        squad,
        line,
        givenBy,
        ...(admin === undefined ? {} : { admin }),
      });
      // Given meanwhile by another call.
      if (gift === undefined) throw new GiftAlreadyOwnedError(piece);
      await deps.gifted?.(member, gift);
      return gift;
    },

    of: (member) => deps.store.giftsOf(member),

    async open(member, piece, worn) {
      if (!(await deps.store.open(member, piece, worn))) throw new GiftNotGivenError(piece);
      const gift = (await deps.store.giftsOf(member)).find((each) => each.piece === piece);
      if (gift === undefined) throw new GiftNotGivenError(piece);
      return gift;
    },

    pieces: () => deps.store.pieces(),

    async putPiece(edit) {
      await deps.store.putPiece(edit);
      return deps.store.pieces();
    },
  };
}
