import { typedText } from '@wildcard/typed-text';
import { z } from 'zod';

// 饮食小目标: up to 3 eating habits a member sets for a week, as the app's 出赛表 has them
// (`FuelGoal` in ios/Packages/Schedule). Habits only: never a body number, a calorie or a macro.

/** How many goals a week holds. */
export const MAX_FUEL_GOALS = 3;

/** The goals the app suggests, by id; their words are the app's. */
export const FuelSuggestion = z.enum([
  'water',
  'cookAtHome',
  'veggies',
  'lessBubbleTea',
  'breakfast',
  'earlyDinner',
]);
export type FuelSuggestion = z.infer<typeof FuelSuggestion>;

/** A goal in the member's own words: trimmed, 1 to 8 characters, one line. */
export const OwnFuelGoal = typedText({
  max: 8,
  oneLine: true,
  description: 'Trimmed, then 1 to 8 characters as people see them, on one line.',
});

export const FuelGoal = z.discriminatedUnion('kind', [
  z.strictObject({ kind: z.literal('suggested'), suggestion: FuelSuggestion }),
  z.strictObject({ kind: z.literal('own'), text: OwnFuelGoal }),
]);
export type FuelGoal = z.infer<typeof FuelGoal>;

const keyOf = (goal: FuelGoal) =>
  goal.kind === 'suggested' ? `suggested:${goal.suggestion}` : `own:${goal.text}`;

/** A week's goals: at most 3, in the order picked, each once. */
export const FuelGoals = z
  .array(FuelGoal)
  .max(MAX_FUEL_GOALS)
  .refine((goals) => new Set(goals.map(keyOf)).size === goals.length, 'Each goal only once');
export type FuelGoals = z.infer<typeof FuelGoals>;

/** The stored goals JSON (`fuel_goals.payload`), versioned like every stored shape. */
export const StoredFuelGoals = z.discriminatedUnion('version', [
  z.strictObject({ version: z.literal(1), goals: FuelGoals }),
]);
