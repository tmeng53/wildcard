import { describe, expect, it } from 'vitest';

import { overGoal, suggestedGoal, type GoalWeek } from './goal-suggestion.js';
import { SceneWeek } from './scene.js';

/** A week of a squad of two with goal 3 a member, unless `squad` says otherwise. */
const week = (
  trainings: number,
  squad: { readonly members?: number; readonly daysPerMember?: number } = {},
): GoalWeek => ({
  week: SceneWeek.parse('2026-10-19'),
  trainings,
  members: squad.members ?? 2,
  daysPerMember: squad.daysPerMember ?? 3,
});

describe('overGoal', () => {
  it('is over only past the goal, never on it, and never for an empty squad', () => {
    expect(overGoal(week(7))).toBe(true);
    expect(overGoal(week(6))).toBe(false);
    expect(overGoal(week(0, { members: 0 }))).toBe(false);
  });
});

describe('suggestedGoal', () => {
  it('rounds the days each member trained over three weeks over the goal', () => {
    // (4 + 4.5 + 4.5) / 3 ≈ 4.33 a member.
    expect(suggestedGoal({ weeks: [week(8), week(9), week(9)], next: 3 })).toBe(4);
    // (4.5 + 4.5 + 4.5) / 3 = 4.5 rounds up.
    expect(suggestedGoal({ weeks: [week(9), week(9), week(9)], next: 3 })).toBe(5);
  });

  it('needs all three weeks over, and a goal above next week’s, at most 7', () => {
    expect(suggestedGoal({ weeks: [week(8), week(6), week(9)], next: 3 })).toBeUndefined();
    expect(suggestedGoal({ weeks: [week(8), week(9)], next: 3 })).toBeUndefined();
    expect(suggestedGoal({ weeks: [week(8), week(8), week(8)], next: 4 })).toBeUndefined();
    const full = week(14, { daysPerMember: 6 });
    expect(suggestedGoal({ weeks: [full, full, full], next: 6 })).toBe(7);
  });
});
