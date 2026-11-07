import {
  boardOf,
  titlesWonOf,
  type Awards,
  type AwardsState,
  type ShownBoardTitle,
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
  SportGlyphs,
} from '../ports.js';
import { shownBadge } from '../domain/badges.js';
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
   * Whether to tell the squad its 战报 is ready: true once, after the awards are written; false
   * for every later call, and before then.
   */
  claimReadyPush(input: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
  }): Promise<boolean>;
  /** Every title the member has won, in all their squads (周奖 on their player card). */
  titlesWon(member: MemberId): Promise<TitlesWon>;
  /**
   * These members' badge boards (徽章板), by member: every title they won in all their squads,
   * the latest first. A member who won nothing has an empty board.
   */
  boards(members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, readonly ShownBoardTitle[]>>;
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
  readonly sportGlyphs: SportGlyphs;
}): WeeklyAwards {
  return {
    give: (input) => giveAwards(deps, input),
    find: ({ squad, weekStart }) => deps.store.find(squad, weekStart),
    claimNudge: ({ squad, weekStart }) => deps.store.claimNudge(squad, weekStart),
    claimReadyPush: ({ squad, weekStart }) => deps.store.markNotified(squad, weekStart),
    titlesWon: async (member) =>
      titlesWonOf(boardOf((await deps.store.wins([member])).get(member) ?? [])),
    boards: async (members) => {
      const [wins, { badges }] = await Promise.all([
        deps.store.wins(members),
        deps.settings.current(),
      ]);
      return new Map(
        members.map((member) => [
          member,
          boardOf(wins.get(member) ?? []).map((title) => ({
            ...title,
            badge: shownBadge(title.badge, badges),
          })),
        ]),
      );
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
