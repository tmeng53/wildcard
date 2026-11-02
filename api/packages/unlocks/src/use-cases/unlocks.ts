import { earned, type MemberId, type Unlock, type UnlockRule } from '../domain/unlocks.js';
import type { UnlockRuleEdit } from '../domain/unlocks.js';
import { UnlockSportNotListedError } from '../errors.js';
import type { SportListed, TrainedSince, UnlockStore } from '../ports.js';

/** What members unlock by training. */
export interface Unlocks {
  /**
   * Everything `member` unlocked, the earliest first. What their check-ins earned since the last
   * read is kept first, so an unlock never goes back, even when its check-in is deleted.
   */
  of(member: MemberId): Promise<Unlock[]>;
}

/** The rules, for admins. */
export interface UnlocksAdmin {
  rules(): Promise<UnlockRule[]>;
  /** Adds or changes a rule and answers with every rule now. */
  putRule(edit: UnlockRuleEdit): Promise<UnlockRule[]>;
}

export function createUnlocks(deps: {
  readonly store: UnlockStore;
  readonly trainedSince: TrainedSince;
  readonly sportListed: SportListed;
}): Unlocks & UnlocksAdmin {
  return {
    async of(member) {
      const [rules, has] = await Promise.all([deps.store.rules(), deps.store.unlocksOf(member)]);
      const held = new Set(has.map(({ kind, id }) => `${kind}:${id}`));
      const open = rules.filter(({ kind, id }) => !held.has(`${kind}:${id}`));
      if (open.length === 0) return has;
      const since = new Date(Math.min(...open.map(({ countsFrom }) => countsFrom.getTime())));
      const trained = await deps.trainedSince({ member, since });
      const fresh = earned({ rules: open, trained, has });
      if (fresh.length === 0) return has;
      await deps.store.grant(member, fresh);
      return deps.store.unlocksOf(member);
    },

    rules: () => deps.store.rules(),

    async putRule(edit) {
      for (const sport of edit.sports) {
        if (!(await deps.sportListed(sport))) throw new UnlockSportNotListedError(sport);
      }
      await deps.store.putRule(edit);
      return deps.store.rules();
    },
  };
}
