import { z } from 'zod';

import { SceneWeek } from './scene.js';
import type { MemberId } from './squad.js';

/**
 * A squad's weekly goal (小队每周目标), as its captain sets it: how many times each member trains
 * on average (人均 N 次). The squad's goal for a week is that times its members, and anyone's
 * 训练 count towards it, several on one day each counting.
 */
export const DaysPerMember = z.int().min(1).max(7);
export type DaysPerMember = z.infer<typeof DaysPerMember>;

/** The goal of a squad nobody set one for, and of a new squad unless its creator picks one. */
export const DEFAULT_DAYS_PER_MEMBER: DaysPerMember = 3;

/** One setting of a squad's goal, and the week (a Monday) it counts from. */
export interface WeeklyGoalSetting {
  readonly week: SceneWeek;
  readonly daysPerMember: DaysPerMember;
  /** Null once the setter deletes their account. */
  readonly by: MemberId | null;
  readonly at: Date;
}

/**
 * The goal for the week starting `week`: the newest setting counting from that week or before,
 * else the default. `settings` are the earliest week first, a week's later settings after its
 * earlier ones.
 */
export function goalFor(settings: readonly WeeklyGoalSetting[], week: SceneWeek): DaysPerMember {
  let goal = DEFAULT_DAYS_PER_MEMBER;
  for (const setting of settings) {
    if (setting.week <= week) goal = setting.daysPerMember;
  }
  return goal;
}

/** The Monday a week after `week`. */
export function weekAfter(week: SceneWeek): SceneWeek {
  return SceneWeek.parse(new Date(Date.parse(week) + 7 * 86_400_000).toISOString().slice(0, 10));
}
