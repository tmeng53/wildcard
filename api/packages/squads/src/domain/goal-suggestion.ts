import { SceneWeek } from './scene.js';
import type { MemberId } from './squad.js';
import { DaysPerMember } from './weekly-goal.js';

/** How many weeks in a row over the goal before the captain is told (连续 3 周超过小队目标). */
export const SUGGESTION_WEEKS = 3;

/** One of a squad's weeks against its goal. */
export interface GoalWeek {
  readonly week: SceneWeek;
  /** Days anyone trained for the squad, once a member a day. */
  readonly trainedDays: number;
  /** Members in the squad at the week's end (now, for a week not over). */
  readonly members: number;
  /** The week's goal, 人均 N 天. */
  readonly daysPerMember: DaysPerMember;
}

/** A higher goal suggested to a squad's captain, and the week whose 战报 told it. */
export interface GoalSuggestion {
  readonly week: SceneWeek;
  /** Null once they deleted their account. */
  readonly captain: MemberId | null;
  readonly daysPerMember: DaysPerMember;
}

/** Whether the squad trained more days than its goal that week (only over counts, never equal). */
export function overGoal(week: GoalWeek): boolean {
  return week.members > 0 && week.trainedDays > week.daysPerMember * week.members;
}

/**
 * The goal to suggest after `weeks`, the latest `SUGGESTION_WEEKS` weeks oldest first: every one
 * over its goal, and the days each member trained on average in them, rounded and at most 7, above
 * `next`, the goal the squad has from next week. `undefined` when there is nothing to suggest.
 */
export function suggestedGoal(input: {
  readonly weeks: readonly GoalWeek[];
  readonly next: DaysPerMember;
}): DaysPerMember | undefined {
  const { weeks, next } = input;
  if (weeks.length < SUGGESTION_WEEKS || !weeks.every(overGoal)) return undefined;
  const mean = weeks.reduce((sum, week) => sum + week.trainedDays / week.members, 0) / weeks.length;
  const suggested = Math.min(7, Math.round(mean));
  return suggested > next ? DaysPerMember.parse(suggested) : undefined;
}

/** The Monday `count` weeks before `week`. */
export function weeksBefore(week: SceneWeek, count: number): SceneWeek {
  return SceneWeek.parse(
    new Date(Date.parse(week) - count * 7 * 86_400_000).toISOString().slice(0, 10),
  );
}
