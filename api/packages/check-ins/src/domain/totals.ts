import type { CheckInId } from './check-in.js';
import type { SportKey } from './sports.js';

/** The sport a member logged the most 训练 for, with how many. */
export interface TopSport {
  readonly sport: SportKey;
  /** The name of a `custom` sport; a listed sport has none. */
  readonly customSport?: string;
  /** 训练 check-ins of this sport. */
  readonly checkIns: number;
}

/** Everything a member ever checked in, counted by kind; 我 shows them. Counts only go up. */
export interface CheckInTotals {
  /** Days with a 训练. Several 训练 on one day count once. */
  readonly trainedDays: number;
  readonly healthyMeals: number;
  readonly cheatMeals: number;
  /** 今日请假条 posted, any number a day. */
  readonly disclaimers: number;
  /**
   * The sport with the most 训练 (a custom sport counts by its name), the latest one on a tie;
   * none before the first 训练.
   */
  readonly topSport?: TopSport;
}

/** A 训练 check-in's sport and when it was made, for what members unlock by training. */
export interface TrainedCheckIn {
  readonly id: CheckInId;
  /** The listed sport, or `custom` for one the member named. */
  readonly sport: SportKey;
  /** The day it counts for (`YYYY-MM-DD`, the member's own day), apart from when it was made. */
  readonly day: string;
  readonly madeAt: Date;
}

/** One 训练 on the member's training record (训练记录): its day, sport and minutes. */
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
