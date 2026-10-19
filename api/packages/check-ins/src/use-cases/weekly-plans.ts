import type { MemberId } from '../domain/check-in.js';
import {
  DEFAULT_PLAN_DAYS,
  checkPlanChange,
  localDayAt,
  type PlanDays,
  type WeekStart,
  type WeeklyPlan,
} from '../domain/weekly-plan.js';
import { TimeZoneNotSetError } from '../errors.js';
import type { Clock, MemberCalendar, WeeklyPlanStore } from '../ports.js';

interface Deps {
  readonly store: WeeklyPlanStore;
  readonly calendarOf: MemberCalendar;
  readonly clock: Clock;
}

/** Members' weekly plans: reading a week's plan and changing it. */
export interface WeeklyPlans {
  /** The member's plan for a week, whether saved for it, carried over or the default. */
  find(input: { readonly member: MemberId; readonly weekStart: WeekStart }): Promise<WeeklyPlan>;
  /**
   * Saves the member's plan for a week and returns it. Throws `TimeZoneNotSetError` before the
   * member has a profile, and the errors of `checkPlanChange` for a change the rules don't allow.
   * Repeating a save gives the same result, so a save can be retried.
   */
  save(input: {
    readonly member: MemberId;
    readonly weekStart: WeekStart;
    readonly days: PlanDays;
  }): Promise<WeeklyPlan>;
}

/** The member's plan for a week: saved for it, carried over from an earlier week, or the default. */
export async function findWeeklyPlan(
  { store }: { readonly store: WeeklyPlanStore },
  { member, weekStart }: { readonly member: MemberId; readonly weekStart: WeekStart },
): Promise<WeeklyPlan> {
  const latest = await store.latestFrom(member, weekStart);
  if (latest === undefined) return { weekStart, days: DEFAULT_PLAN_DAYS, source: 'default' };
  return {
    weekStart,
    days: latest.days,
    source: latest.weekStart === weekStart ? 'saved' : 'carriedOver',
  };
}

export function createWeeklyPlans(deps: Deps): WeeklyPlans {
  return {
    find: (input) => findWeeklyPlan(deps, input),
    async save({ member, weekStart, days }) {
      const calendar = await deps.calendarOf(member);
      if (calendar === undefined) throw new TimeZoneNotSetError();
      const { timeZone, joinedAt } = calendar;
      const current = await findWeeklyPlan(deps, { member, weekStart });
      checkPlanChange({
        current,
        next: days,
        today: localDayAt(deps.clock(), timeZone),
        joinedOn: localDayAt(joinedAt, timeZone),
      });
      await deps.store.save({ member, weekStart, days });
      return { weekStart, days, source: 'saved' };
    },
  };
}
