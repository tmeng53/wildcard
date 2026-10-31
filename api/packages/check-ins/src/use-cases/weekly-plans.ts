import type { LocalDay, MemberId } from '../domain/check-in.js';
import type { FuelGoals } from '../domain/fuel-goal.js';
import {
  DEFAULT_PLAN_DAYS,
  WeekStart,
  addDays,
  checkFuelGoalsChange,
  checkPlanChange,
  localDayAt,
  trainedOnRestDay,
  weekStartOf,
  type PlanDays,
  type WeeklyPlan,
} from '../domain/weekly-plan.js';
import { TimeZoneNotSetError } from '../errors.js';
import type { Clock, MemberCalendar, SportList, WeeklyPlanStore } from '../ports.js';
import { checkSport } from './check-sport.js';

interface Deps {
  readonly store: WeeklyPlanStore;
  /** Which sports a planned day may name. */
  readonly sports: SportList;
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

/** A member's typical week (我的一周): the plan each week follows until it is changed for itself. */
export interface PlanTemplate {
  readonly days: PlanDays;
  /** `default` before the member makes one. */
  readonly source: 'saved' | 'default';
}

/** Members' weekly plans and typical weeks: reading a week's plan and changing it. */
export interface WeeklyPlans {
  /** The member's plan for a week, whether saved for it, their template or the default. */
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
  /** The member's template: the one the weeks to come follow, or the default before they make one. */
  template(input: { readonly member: MemberId }): Promise<PlanTemplate>;
  /**
   * Saves the member's template and returns it. The first one, made at sign-up, applies from
   * this week; a change applies from next week, so a week that has begun keeps its plan. Throws
   * `TimeZoneNotSetError` before the member has a profile. Safe to repeat.
   */
  saveTemplate(input: {
    readonly member: MemberId;
    readonly days: PlanDays;
  }): Promise<PlanTemplate>;
}

/** The member's plan for a week: saved for it, else their template, else the default. */
export async function findWeeklyPlan(
  { store }: { readonly store: WeeklyPlanStore },
  { member, weekStart }: { readonly member: MemberId; readonly weekStart: WeekStart },
): Promise<WeeklyPlan> {
  const [saved, template] = await Promise.all([
    store.savedFor(member, weekStart),
    store.templateFor(member, weekStart),
  ]);
  if (saved !== undefined) return { weekStart, days: saved, source: 'saved' };
  if (template !== undefined) return { weekStart, days: template, source: 'template' };
  return { weekStart, days: DEFAULT_PLAN_DAYS, source: 'default' };
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

  /** Throws `SportNotListedError` for a day naming a sport the list doesn't have. */
  async function checkSports(days: PlanDays) {
    for (const day of days) {
      if (day.kind === 'train' && day.sport !== undefined) await checkSport(deps.sports, day.sport);
    }
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
      await checkSports(days);
      await deps.store.save({ member, weekStart, days });
      return plannedWeek({ member, joinedOn }, { weekStart, days, source: 'saved' });
    },
    async template({ member }) {
      const latest = await deps.store.latestTemplate(member);
      return latest === undefined
        ? { days: DEFAULT_PLAN_DAYS, source: 'default' }
        : { days: latest.days, source: 'saved' };
    },
    async saveTemplate({ member, days }) {
      const { today } = await daysOf(member);
      await checkSports(days);
      const thisWeek = weekStartOf(today);
      const latest = await deps.store.latestTemplate(member);
      const fromWeek = latest === undefined ? thisWeek : WeekStart.parse(addDays(thisWeek, 7));
      await deps.store.saveTemplate({ member, fromWeek, days });
      return { days, source: 'saved' };
    },
    async saveFuelGoals({ member, weekStart, goals }) {
      const { today, joinedOn } = await daysOf(member);
      checkFuelGoalsChange({ weekStart, today });
      await deps.store.saveFuelGoals({ member, weekStart, goals });
      return plannedWeek({ member, joinedOn }, await findWeeklyPlan(deps, { member, weekStart }));
    },
  };
}
