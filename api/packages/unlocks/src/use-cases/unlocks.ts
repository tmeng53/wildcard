import {
  earned,
  toGo,
  type Claim,
  type Locked,
  type PieceId,
  type MemberId,
  type Unlock,
  type UnlockRule,
} from '../domain/unlocks.js';
import type { UnlockGift, UnlockRuleEdit } from '../domain/unlocks.js';
import {
  PieceNotUnlockedError,
  UnlockItemMissingError,
  UnlockSportNotListedError,
} from '../errors.js';
import type { SportListed, TrainedSince, UnlockStore, Unlocked } from '../ports.js';

/** What members unlock by training. */
export interface Unlocks {
  /**
   * Everything `member` unlocked, the earliest first. What their check-ins earned since the last
   * read is kept first, so an unlock never goes back, even when its check-in is deleted.
   */
  of(member: MemberId): Promise<Unlock[]>;
  /** What `member` unlocked, as `of` keeps it, and how far they are from everything else. */
  standing(member: MemberId): Promise<{ unlocks: Unlock[]; locked: Locked[] }>;
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
}

export function createUnlocks(deps: {
  readonly store: UnlockStore;
  readonly trainedSince: TrainedSince;
  readonly sportListed: SportListed;
  /** Told what each grant kept new; left out where nobody needs telling. */
  readonly unlocked?: Unlocked;
}): Unlocks & UnlocksAdmin {
  const grant = async (member: MemberId, unlocks: readonly Unlock[]) => {
    const kept = await deps.store.grant(member, unlocks);
    if (kept.length > 0) await deps.unlocked?.(member, kept);
  };
  const standing = async (member: MemberId) => {
    const [rules, has] = await Promise.all([deps.store.rules(), deps.store.unlocksOf(member)]);
    const held = new Set(has.map(({ kind, id }) => `${kind}:${id}`));
    const open = rules.filter(({ kind, id }) => !held.has(`${kind}:${id}`));
    if (open.length === 0) return { unlocks: has, locked: [] };
    const since = new Date(Math.min(...open.map(({ countsFrom }) => countsFrom.getTime())));
    const trained = await deps.trainedSince({ member, since });
    const fresh = earned({ rules: open, trained, has });
    const locked = toGo({ rules: open, trained });
    if (fresh.length === 0) return { unlocks: has, locked };
    await grant(member, fresh);
    return { unlocks: await deps.store.unlocksOf(member), locked };
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
  };
}
