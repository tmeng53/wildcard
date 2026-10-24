import type { LocalDay, MemberId } from '../domain/check-in.js';
import type { FuelGoals } from '../domain/fuel-goal.js';
import {
  DEFAULT_PLAN_DAYS,
  checkFuelGoalsChange,
  checkPlanChange,
  localDayAt,
  trainedOnRestDay,
  weekStartOf,
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

/** A member's week as the 出赛表 shows it: the plan, the week's 饮食小目标 and how far back to look. */
export interface PlannedWeek extends WeeklyPlan {
  /** Only those saved for this week: goals don't carry over. */
  readonly fuelGoals: FuelGoals;
  /** The Monday of the week the member joined, in their time zone; none before their profile. */
  readonly firstWeek: WeekStart | undefined;
}

/** Members' weekly plans: reading a week's plan and changing it. */
export interface WeeklyPlans {
  /** The member's plan for a week, whether saved for it, carried over or the default. */
  find(input: { readonly member: MemberId; readonly weekStart: WeekStart }): Promise<PlannedWeek>;
  /**
   * Saves the member's plan for a week and returns it. Throws `TimeZoneNotSetError` before the
   * member has a profile, and the errors of `checkPlanChange` for a change the rules don't allow.
   * Repeating a save gives the same result, so a save can be retried.
   */
  save(input: {
    readonly member: MemberId;
    readonly weekStart: WeekStart;
    readonly days: PlanDays;
  }): Promise<PlannedWeek>;
  /**
   * Saves the member's 饮食小目标 for this week or a later one and returns the week. Throws
   * `TimeZoneNotSetError` before the member has a profile, and the errors of
   * `checkFuelGoalsChange` otherwise. Safe to repeat.
   */
  saveFuelGoals(input: {
    readonly member: MemberId;
    readonly weekStart: WeekStart;
    readonly goals: FuelGoals;
  }): Promise<PlannedWeek>;
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

/**
 * Makes `day` a training day of the 练了's sport in the member's plan when it was a rest day, so
 * training on a planned rest day counts in the week like any training day. Safe to repeat.
 */
export async function planTrainedDay(
  { store }: { readonly store: WeeklyPlanStore },
  {
    member,
    day,
    training,
  }: {
    readonly member: MemberId;
    readonly day: LocalDay;
    readonly training: Parameters<typeof trainedOnRestDay>[0]['training'];
  },
): Promise<void> {
  const plan = await findWeeklyPlan({ store }, { member, weekStart: weekStartOf(day) });
  const days = trainedOnRestDay({ plan, day, training });
  if (days !== undefined) await store.save({ member, weekStart: plan.weekStart, days });
}

export function createWeeklyPlans(deps: Deps): WeeklyPlans {
  /** The member's today and the day they joined, on their clock; throws before their profile. */
  async function daysOf(member: MemberId) {
    const calendar = await deps.calendarOf(member);
    if (calendar === undefined) throw new TimeZoneNotSetError();
    const { timeZone, joinedAt } = calendar;
    return { today: localDayAt(deps.clock(), timeZone), joinedOn: localDayAt(joinedAt, timeZone) };
  }

  async function plannedWeek(
    { member, joinedOn }: { readonly member: MemberId; readonly joinedOn: LocalDay | undefined },
    plan: WeeklyPlan,
  ): Promise<PlannedWeek> {
    const fuelGoals = await deps.store.fuelGoals(member, plan.weekStart);
    return {
      ...plan,
      fuelGoals: fuelGoals ?? [],
      firstWeek: joinedOn === undefined ? undefined : weekStartOf(joinedOn),
    };
  }

  return {
    async find(input) {
      const [plan, calendar] = await Promise.all([
        findWeeklyPlan(deps, input),
        deps.calendarOf(input.member),
      ]);
      const joinedOn =
        calendar === undefined ? undefined : localDayAt(calendar.joinedAt, calendar.timeZone);
      return plannedWeek({ member: input.member, joinedOn }, plan);
    },
    async save({ member, weekStart, days }) {
      const { today, joinedOn } = await daysOf(member);
      const current = await findWeeklyPlan(deps, { member, weekStart });
      checkPlanChange({ current, next: days, today, joinedOn });
      await deps.store.save({ member, weekStart, days });
      return plannedWeek({ member, joinedOn }, { weekStart, days, source: 'saved' });
    },
    async saveFuelGoals({ member, weekStart, goals }) {
      const { today, joinedOn } = await daysOf(member);
      checkFuelGoalsChange({ weekStart, today });
      await deps.store.saveFuelGoals({ member, weekStart, goals });
      return plannedWeek({ member, joinedOn }, await findWeeklyPlan(deps, { member, weekStart }));
    },
  };
}
