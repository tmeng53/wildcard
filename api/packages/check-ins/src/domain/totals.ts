import type { CheckInId } from './check-in.js';
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
  /** 今日请假条 posted, any number a day. */
  readonly disclaimers: number;
  /**
   * The sport with the most 练了 (a custom sport counts by its name), the latest one on a tie;
   * none before the first 练了.
   */
  readonly topSport?: TopSport;
}

/** A 练了 check-in's sport and when it was made, for what members unlock by training. */
export interface TrainedCheckIn {
  readonly id: CheckInId;
  /** The listed sport, or `custom` for one the member named. */
  readonly sport: SportKey;
  readonly madeAt: Date;
}

/** One 练了 on the member's training record (训练记录): its day, sport and minutes. */
export interface TrainingDay {
  readonly id: CheckInId;
  /** The day it counts for. */
  readonly day: string;
  readonly sport: SportKey;
  /** The name of a `custom` sport; a listed sport has none. */
  readonly customSport?: string;
  /** How long it took, when the member said. */
  readonly minutes?: number;
}
