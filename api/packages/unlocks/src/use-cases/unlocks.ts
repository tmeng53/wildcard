import {
  earned,
  shelf,
  toGo,
  type CountedRule,
  type Claim,
  type SwitchOn,
  type Locked,
  type PieceId,
  type MemberId,
  type Piece,
  type Shelf,
  type Store,
  type Unlock,
  type UnlockRule,
} from '../domain/unlocks.js';
import type { PieceEdit, StoreEdit, UnlockGift, UnlockRuleEdit } from '../domain/unlocks.js';
import {
  PieceNotUnlockedError,
  UnlockItemMissingError,
  UnlockSportNotListedError,
  UnlockStoreMissingError,
} from '../errors.js';
import type { SportListed, TrainedSince, UnlockStore, Unlocked } from '../ports.js';

/** What members unlock by training. */
export interface Unlocks {
  /**
   * Everything `member` unlocked, the earliest first. What their check-ins earned since the last
   * read is kept first, so an unlock never goes back, even when its check-in is deleted.
   */
  of(member: MemberId): Promise<Unlock[]>;
  /**
   * What `member` unlocked, as `of` keeps it, how far they are from everything else, and the
   * 商店街 as it stands for them now.
   */
  standing(member: MemberId): Promise<{ unlocks: Unlock[]; locked: Locked[]; shelf: Shelf }>;
  /** The pieces `member` claimed into their wardrobe, the earliest first. */
  claimsOf(member: MemberId): Promise<Claim[]>;
  /**
   * 领取: puts `piece`, which `member` unlocked, in their wardrobe; claiming it again keeps the
   * first claim.
   */
  claim(member: MemberId, piece: PieceId): Promise<Claim>;
}

/** The rules, for admins. */
export interface UnlocksAdmin {
  rules(): Promise<UnlockRule[]>;
  /** Adds or changes a rule and answers with every rule now. */
  putRule(edit: UnlockRuleEdit): Promise<UnlockRule[]>;
  /**
   * Gives `gift.member` the stores, props and pieces it names (every one with a rule when it names none)
   * from `admin`, now; what they already hold stays as it was. Answers with all they hold.
   */
  give(gift: UnlockGift, admin: MemberId): Promise<Unlock[]>;
  /** Every store, retired ones too, in the street's order. */
  stores(): Promise<Store[]>;
  /** Adds or replaces a store and answers with every store now. */
  putStore(edit: StoreEdit): Promise<Store[]>;
  /** Every piece, retired ones too. */
  pieces(): Promise<Piece[]>;
  /** Adds or replaces a piece in a store that exists and answers with every piece now. */
  putPiece(edit: PieceEdit): Promise<Piece[]>;
}

/**
 * Each rule with the switches it counts under: a piece's rule under the piece's own and its
 * store's, a store's rule under the store's, a prop's under none.
 */
function counted(
  rules: readonly UnlockRule[],
  { stores, pieces }: { readonly stores: readonly Store[]; readonly pieces: readonly Piece[] },
): CountedRule[] {
  const storeSwitch = new Map(stores.map(({ id, switchId }) => [id, switchId]));
  const pieceSwitches = new Map(
    pieces.map(({ id, storeId, switchId }) => [id, [switchId, storeSwitch.get(storeId)]]),
  );
  return rules.map((rule) => {
    const named =
      rule.kind === 'piece'
        ? (pieceSwitches.get(rule.id) ?? [])
        : rule.kind === 'store'
          ? [storeSwitch.get(rule.id)]
          : [];
    return { ...rule, switchIds: named.filter((id) => id !== undefined) };
  });
}

export function createUnlocks(deps: {
  readonly store: UnlockStore;
  readonly trainedSince: TrainedSince;
  readonly sportListed: SportListed;
  /** Every switch as it is now, as one lookup. */
  readonly switches: (member: MemberId) => Promise<SwitchOn>;
  /** Told what each grant kept new; left out where nobody needs telling. */
  readonly unlocked?: Unlocked;
}): Unlocks & UnlocksAdmin {
  const grant = async (member: MemberId, unlocks: readonly Unlock[]) => {
    const kept = await deps.store.grant(member, unlocks);
    if (kept.length > 0) await deps.unlocked?.(member, kept);
  };
  const standing = async (member: MemberId) => {
    const [rules, has, stores, pieces, switchOn] = await Promise.all([
      deps.store.rules(),
      deps.store.unlocksOf(member),
      deps.store.stores(),
      deps.store.pieces(),
      deps.switches(member),
    ]);
    const now = new Date();
    const on = (id: string) => switchOn(id, now);
    const held = new Set(has.map(({ kind, id }) => `${kind}:${id}`));
    // A retired store or piece, or a piece in a retired store, is neither earned nor boxed any
    // more; what was earned stays.
    const retiredStores = new Set(stores.filter(({ offered }) => !offered).map(({ id }) => id));
    const retired = new Set([
      ...[...retiredStores].map((id) => `store:${id}`),
      ...pieces
        .filter(({ offered, storeId }) => !offered || retiredStores.has(storeId))
        .map(({ id }) => `piece:${id}`),
    ]);
    const open = counted(
      rules.filter(({ kind, id }) => !held.has(`${kind}:${id}`) && !retired.has(`${kind}:${id}`)),
      { stores, pieces },
    );
    const trained =
      open.length === 0
        ? []
        : await deps.trainedSince({
            member,
            since: new Date(Math.min(...open.map(({ countsFrom }) => countsFrom.getTime()))),
          });
    const fresh = earned({ rules: open, trained, has, switchOn });
    const locked = toGo({ rules: open, trained, switchOn });
    if (fresh.length > 0) await grant(member, fresh);
    const unlocks = fresh.length === 0 ? has : await deps.store.unlocksOf(member);
    return { unlocks, locked, shelf: shelf({ stores, pieces, rules, has: unlocks, locked, on }) };
  };
  return {
    of: async (member) => (await standing(member)).unlocks,
    standing,

    claimsOf: (member) => deps.store.claimsOf(member),

    async claim(member, piece) {
      // What their training earned since the last read counts, so a piece just reached can be claimed.
      await standing(member);
      const claim = await deps.store.claim(member, piece);
      if (claim === undefined) throw new PieceNotUnlockedError(piece);
      return claim;
    },

    rules: () => deps.store.rules(),

    async putRule(edit) {
      for (const sport of edit.sports) {
        if (!(await deps.sportListed(sport))) throw new UnlockSportNotListedError(sport);
      }
      await deps.store.putRule(edit);
      return deps.store.rules();
    },

    async give({ member, items }, admin) {
      const rules = await deps.store.rules();
      const named = new Set(items?.map(({ kind, id }) => `${kind}:${id}`));
      for (const item of named) {
        if (!rules.some(({ kind, id }) => `${kind}:${id}` === item)) {
          throw new UnlockItemMissingError(item);
        }
      }
      const given =
        items === undefined ? rules : rules.filter(({ kind, id }) => named.has(`${kind}:${id}`));
      const unlockedAt = new Date();
      await grant(
        member,
        given.map(({ kind, id, sports, after }) => ({
          kind,
          id,
          sports,
          after,
          by: { admin },
          unlockedAt,
        })),
      );
      return deps.store.unlocksOf(member);
    },

    stores: () => deps.store.stores(),

    async putStore(edit) {
      await deps.store.putStore(edit);
      return deps.store.stores();
    },

    pieces: () => deps.store.pieces(),

    async putPiece(edit) {
      if (!(await deps.store.stores()).some(({ id }) => id === edit.storeId)) {
        throw new UnlockStoreMissingError(edit.storeId);
      }
      await deps.store.putPiece(edit);
      return deps.store.pieces();
    },
  };
}
