import type { LocalDay, MemberId } from '../../domain/check-in.js';
import { addDays, weekStartOf } from '../../domain/weekly-plan.js';
import type { WeeklyPlanStore } from '../../ports.js';
import { findWeeklyPlan } from '../weekly-plans.js';

/** The days the member's plans made rest days, over the weeks from the first of `days` to the last. */
export async function restDays(
  deps: { readonly plans: WeeklyPlanStore },
  { member, days }: { readonly member: MemberId; readonly days: readonly LocalDay[] },
): Promise<Set<LocalDay>> {
  const sorted = [...days].sort();
  const first = sorted[0];
  const last = sorted.at(-1);
  if (first === undefined || last === undefined) return new Set();
  const weeks: LocalDay[] = [];
  for (let week = weekStartOf(first); week <= last; week = addDays(week, 7)) weeks.push(week);
  const plans = await Promise.all(
    weeks.map((weekStart) =>
      findWeeklyPlan({ store: deps.plans }, { member, weekStart: weekStartOf(weekStart) }),
    ),
  );
  return new Set(
    plans.flatMap((plan) =>
      plan.days.flatMap((day, index) =>
        day.kind === 'rest' ? [addDays(plan.weekStart, index)] : [],
      ),
    ),
  );
}
