import type { SportKey } from './sports.js';

/** The sport a member logged the most 练了 for, with how many. */
export interface TopSport {
  readonly sport: SportKey;
  /** The name of a `custom` sport; a listed sport has none. */
  readonly customSport?: string;
  /** 练了 check-ins of this sport. */
  readonly checkIns: number;
}

/** Everything a member ever checked in, counted by kind; 我 shows them. Counts only go up. */
export interface CheckInTotals {
  /** Days with a 练了. Several 练了 on one day count once. */
  readonly trainedDays: number;
  readonly healthyMeals: number;
  readonly cheatMeals: number;
  /** 今日请假条, at most one a day. */
  readonly disclaimers: number;
  /**
   * The sport with the most 练了 (a custom sport counts by its name), the latest one on a tie;
   * none before the first 练了.
   */
  readonly topSport?: TopSport;
}
