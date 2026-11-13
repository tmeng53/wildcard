import { z } from 'zod';

// How a member rated one meal they posted (Tracy, 2026-11-12): 健康 and 好吃, each 1 to 5
// tickets, both or neither. Any meal can carry it, with or without a place; a restaurant's
// scores will be the average of the meals posted there. 卡价比 is worked out from it, never stored.

const Score = z.int().min(1).max(5);

export const MealRating = z
  .strictObject({
    healthy: Score.meta({ description: '健康: how healthy the meal was, 1 to 5.' }),
    tasty: Score.meta({ description: '好吃: how good it tasted, 1 to 5.' }),
  })
  .meta({
    id: 'MealRating',
    description:
      "The member's own rating of this meal: 健康 and 好吃, each 1 to 5. Its 卡价比 is " +
      'tasty × healthy ÷ 5.',
  });
export type MealRating = z.infer<typeof MealRating>;

/** 卡价比 (卡路里性价比): 好吃 × 健康 ÷ 5, from 0.2 to 5 (Tracy, 2026-11-12). */
export function calorieValue(rating: MealRating): number {
  return (rating.tasty * rating.healthy) / 5;
}
