import type { z } from 'zod';

import type {
  Awards,
  AwardsState,
  Failures,
  MemberId,
  SquadId,
  TitlesWon,
} from './domain/awards.js';
import type { WeekStart } from './domain/schedule.js';
import type { WeekStory } from './domain/week-story.js';
import type { AwardSettings, ModelName } from './domain/settings.js';

/**
 * A language model that answers in a set JSON shape, whoever provides it. Throws when it can't
 * be reached, declines to answer, or answers out of shape.
 */
export interface LanguageModel {
  answer<Reply>(request: {
    /** Which model answers, as provider/model. */
    readonly model: ModelName;
    /** The standing instructions (a system prompt). */
    readonly instructions: string;
    /** What to answer. */
    readonly prompt: string;
    /** The shape of the answer. */
    readonly reply: z.ZodType<Reply>;
  }): Promise<Reply>;
}

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
   * Marks a squad's awards for a week as told to its winners; true only for the one call that
   * marks them, false when they were told already or there are none.
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
  /** Every title the member has won, in all their squads. */
  titlesWon(member: MemberId): Promise<TitlesWon>;
}

/** Where each squad's frozen 战报 is kept: written once a week, never changed. */
export interface WeekStoryStore {
  /** A squad's 战报 for a week; `undefined` before it is frozen. */
  find(squad: SquadId, weekStart: WeekStart): Promise<WeekStory | undefined>;
  /** Saves a squad's 战报 for a week unless it has one already: two runs at once keep one. */
  freeze(story: WeekStory): Promise<void>;
}

/**
 * Those of these members who agreed to having their words sent to AI providers (the current
 * copy): only their weeks go to the model.
 */
export type AiConsented = (members: readonly MemberId[]) => Promise<readonly string[]>;
