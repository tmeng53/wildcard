import type { Awards, AwardsState, Failures, MemberId, SquadId } from '../domain/awards.js';
import type { WeekStart } from '../domain/schedule.js';
import type { AwardsStore, LanguageModel } from '../ports.js';
import { giveAwards, type GiveAwardsInput } from './weekly-awards/give-awards.js';

/** Each squad's weekly awards (本周颁奖). */
export interface WeeklyAwards {
  /** A squad's awards for the week, written once and then the same every time. */
  give(input: GiveAwardsInput): Promise<Awards>;
  /** Where a squad's awards for the week stand, or `undefined` before anything happened. */
  find(input: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
  }): Promise<AwardsState | undefined>;
  /**
   * A member nudging the organisers about awards that haven't come: the failed tries so far,
   * once per failed try (and once before the first) however many members nudge; `undefined`
   * otherwise, and once the awards are given.
   */
  claimNudge(input: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
  }): Promise<Failures | undefined>;
  /**
   * The members to tell they won something: every member with an award, once. Empty for every
   * later call, and before the awards are written.
   */
  claimWinners(input: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
  }): Promise<MemberId[]>;
}

export function createWeeklyAwards(deps: {
  readonly model: LanguageModel;
  readonly store: AwardsStore;
}): WeeklyAwards {
  return {
    give: (input) => giveAwards(deps, input),
    find: ({ squad, weekStart }) => deps.store.find(squad, weekStart),
    claimNudge: ({ squad, weekStart }) => deps.store.claimNudge(squad, weekStart),
    claimWinners: async ({ squad, weekStart }) => {
      const state = await deps.store.find(squad, weekStart);
      if (state?.status !== 'given' || state.awards.members.length === 0) return [];
      if (!(await deps.store.markNotified(squad, weekStart))) return [];
      return state.awards.members.map(({ member }) => member);
    },
  };
}
