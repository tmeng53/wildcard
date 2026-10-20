import type { MemberId, SquadId, StoredAwards } from '../domain/awards.js';
import type { WeekStart } from '../domain/schedule.js';
import type { AwardsStore, LanguageModel } from '../ports.js';
import { giveAwards, type GiveAwardsInput } from './weekly-awards/give-awards.js';

/** Each squad's weekly awards (本周颁奖). */
export interface WeeklyAwards {
  /** A squad's awards for the week, written once and then the same every time. */
  give(input: GiveAwardsInput): Promise<StoredAwards>;
  /** A squad's awards for the week, or `undefined` before they are written. */
  find(input: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
  }): Promise<StoredAwards | undefined>;
  /**
   * The members to tell they won something: every member with an award, once. Empty for every
   * later call, and before the awards are written.
   */
  claimWinners(input: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
  }): Promise<MemberId[]>;
  /** Takes a member out of every squad's awards, for an account being deleted. */
  forget(member: MemberId): Promise<void>;
}

export function createWeeklyAwards(deps: {
  readonly model: LanguageModel;
  readonly store: AwardsStore;
}): WeeklyAwards {
  return {
    give: (input) => giveAwards(deps, input),
    find: ({ squad, weekStart }) => deps.store.find(squad, weekStart),
    claimWinners: async ({ squad, weekStart }) => {
      const awards = await deps.store.find(squad, weekStart);
      if (awards === undefined || awards.members.length === 0) return [];
      if (!(await deps.store.markNotified(squad, weekStart))) return [];
      return awards.members.map(({ member }) => member);
    },
    forget: (member) => deps.store.forget(member),
  };
}
