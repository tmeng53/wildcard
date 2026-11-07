import type {
  Awards,
  AwardsState,
  Failures,
  MemberId,
  SquadId,
  TitleWin,
} from './domain/awards.js';
import type { PromptMeme } from './domain/prompt.js';
import type { WeekStart } from './domain/schedule.js';
import type { WeekStory } from './domain/week-story.js';
import type { AwardSettings } from './domain/settings.js';

/** Where the award settings are kept: one value, and a log of every change to it. */
export interface AwardSettingsStore {
  /**
   * The settings now. `forUpdate` holds the row until the caller's transaction ends, so two
   * admins changing them at once apply one change after the other.
   */
  current(options?: { readonly forUpdate?: boolean }): Promise<AwardSettings>;
  /**
   * Saves `settings` with `by` as who changed them, unless they are the settings already: then
   * nothing is saved or logged. Says whether anything changed.
   */
  save(settings: AwardSettings, by: MemberId): Promise<boolean>;
}

/** Where each squad's awards are kept: once a week, never rewritten, and the tries before. */
export interface AwardsStore {
  /** Where a squad's awards for a week stand; `undefined` before anything happened to them. */
  find(squad: SquadId, weekStart: WeekStart): Promise<AwardsState | undefined>;
  /**
   * Saves a squad's awards for a week unless it has some already; says whether these were
   * saved, so two runs at once keep one.
   */
  save(awards: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
    readonly awards: Awards;
  }): Promise<boolean>;
  /**
   * Marks a squad's 战报 for a week as told to the squad; true only for the one call that marks
   * it, false when it was told already or its awards aren't written yet.
   */
  markNotified(squad: SquadId, weekStart: WeekStart): Promise<boolean>;
  /** Counts a failed try at a squad's awards for a week, keeping why it failed. */
  recordFailure(failure: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
    readonly error: string;
  }): Promise<void>;
  /**
   * Claims a nudge about a squad's awards for a week that aren't given: the failed tries so far
   * when none was claimed since the last failed try, else `undefined`, as it is once given.
   */
  claimNudge(squad: SquadId, weekStart: WeekStart): Promise<Failures | undefined>;
  /**
   * Every title these members have won, in all their squads, by member: the latest week first,
   * each week's titles in the order given. A member who won nothing is left out.
   */
  wins(members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, readonly TitleWin[]>>;
}

/** Where each squad's frozen 战报 is kept: written once a week, never changed. */
export interface WeekStoryStore {
  /** A squad's 战报 for a week; `undefined` before it is frozen. */
  find(squad: SquadId, weekStart: WeekStart): Promise<WeekStory | undefined>;
  /** Saves a squad's 战报 for a week unless it has one already: two runs at once keep one. */
  freeze(story: WeekStory): Promise<void>;
  /**
   * The squads with a 战报 frozen for the week and no awards given yet, so the job finishes them
   * even after the check-ins that started them were deleted.
   */
  waitingForAwards(weekStart: WeekStart): Promise<SquadId[]>;
}

/**
 * Those of these members who agreed to having their words sent to AI providers (the current
 * copy): only their weeks go to the model.
 */
export type AiConsented = (members: readonly MemberId[]) => Promise<readonly string[]>;

/** The memes in use, from the meme library. */
export type MemesInUse = () => Promise<readonly PromptMeme[]>;
