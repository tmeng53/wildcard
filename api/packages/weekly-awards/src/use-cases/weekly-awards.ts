import {
  boardOf,
  titlesWonOf,
  type Awards,
  type AwardsState,
  type BoardTitle,
  type Failures,
  type MemberId,
  type SquadId,
  type TitlesWon,
} from '../domain/awards.js';
import type { WeekStart } from '../domain/schedule.js';
import type { WeekStory } from '../domain/week-story.js';
import type {
  AiConsented,
  AwardSettingsStore,
  AwardsStore,
  LanguageModel,
  WeekStoryStore,
  MemesInUse,
} from '../ports.js';
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
  /** Every title the member has won, in all their squads (周奖 on their player card). */
  titlesWon(member: MemberId): Promise<TitlesWon>;
  /**
   * These members' badge boards (徽章板), by member: every title they won in all their squads,
   * the latest first. A member who won nothing has an empty board.
   */
  boards(members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, readonly BoardTitle[]>>;
  /** A squad's frozen 战报 for the week, or `undefined` before it is frozen. */
  story(input: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
  }): Promise<WeekStory | undefined>;
  /**
   * Freezes a squad's 战报 for the week, unless it is frozen already, and returns the one that
   * stands.
   */
  freezeStory(story: WeekStory): Promise<WeekStory>;
  /** The squads whose 战报 for the week is frozen and still waits for its awards. */
  storiesWaiting(input: { readonly weekStart: WeekStart }): Promise<SquadId[]>;
}

export function createWeeklyAwards(deps: {
  readonly model: LanguageModel;
  readonly settings: AwardSettingsStore;
  readonly store: AwardsStore;
  readonly aiConsented: AiConsented;
  readonly stories: WeekStoryStore;
  readonly memes: MemesInUse;
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
    titlesWon: async (member) =>
      titlesWonOf(boardOf((await deps.store.wins([member])).get(member) ?? [])),
    boards: async (members) => {
      const wins = await deps.store.wins(members);
      return new Map(members.map((member) => [member, boardOf(wins.get(member) ?? [])]));
    },
    story: ({ squad, weekStart }) => deps.stories.find(squad, weekStart),
    storiesWaiting: ({ weekStart }) => deps.stories.waitingForAwards(weekStart),
    freezeStory: async (story) => {
      await deps.stories.freeze(story);
      const frozen = await deps.stories.find(story.squad, story.weekStart);
      if (frozen === undefined) throw new Error('A 战报 was frozen but can’t be read back');
      return frozen;
    },
  };
}
