/** Everything a member ever checked in, counted by kind; 我 shows them. Counts only go up. */
export interface CheckInTotals {
  /** Days with a 练了. Several 练了 on one day count once. */
  readonly trainedDays: number;
  readonly healthyMeals: number;
  readonly cheatMeals: number;
  /** 今日请假条, at most one a day. */
  readonly disclaimers: number;
}
