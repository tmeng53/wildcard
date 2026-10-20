import type { z } from 'zod';

import type { Awards, AwardsState, Failures, SquadId } from './domain/awards.js';
import type { WeekStart } from './domain/schedule.js';

/**
 * A language model that answers in a set JSON shape, whoever provides it. Throws when it can't
 * be reached, declines to answer, or answers out of shape.
 */
export interface LanguageModel {
  answer<Reply>(request: {
    /** The standing instructions (a system prompt). */
    readonly instructions: string;
    /** What to answer. */
    readonly prompt: string;
    /** The shape of the answer. */
    readonly reply: z.ZodType<Reply>;
  }): Promise<Reply>;
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
}
