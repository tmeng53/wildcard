import type { MemberId, SquadId } from '../../domain/check-in.js';
import { markOn, trainedDays, weekOf, type DayMark } from '../../domain/days.js';
import type { FuelGoals } from '../../domain/fuel-goal.js';
import {
  localDayAt,
  plannedTrainingDays,
  WeekStart,
  type PlanDays,
} from '../../domain/weekly-plan.js';
import type { CheckInStore, Clock, MemberCalendar, WeeklyPlanStore } from '../../ports.js';
import { findWeeklyPlan } from '../weekly-plans.js';
import { zonesOf } from './member-zones.js';

/**
 * A member's week as a squadmate sees it, this week only: 本周 x/y (days trained against the days
 * their plan trains), the plan's seven days, how each went, and the week's 饮食小目标.
 */
export interface MemberWeek {
  readonly trainedDays: number;
  readonly plannedDays: number;
  readonly weekStart: WeekStart;
  readonly days: PlanDays;
  /** Seven, Monday first. */
  readonly marks: readonly DayMark[];
  readonly fuelGoals: FuelGoals;
}

/**
 * A member's own week as their player card shows it to a squadmate: their days trained, from all
 * their check-ins wherever they went, against their plan, in their own time zone (else the
 * viewer's), as the home counts the viewer's own week; and the card's back, their 出赛表 for this
 * week only (never another week's), whose marks come only from the posts shared to the squad the
 * card is read in, so a squadmate never learns what a post they can't see was.
 */
export async function memberWeek(
  deps: {
    readonly store: CheckInStore;
    readonly plans: WeeklyPlanStore;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  {
    member,
    viewer,
    squad,
  }: { readonly member: MemberId; readonly viewer: MemberId; readonly squad: SquadId },
): Promise<MemberWeek> {
  const zones = await zonesOf(deps.calendarOf, { members: [member, viewer], viewer });
  const { zone, joinedOn } = zones[0] ?? { zone: 'UTC', joinedOn: undefined };
  const week = weekOf(localDayAt(deps.clock(), zone));
  const weekStart = WeekStart.parse(week.from);
  const [plan, theirs, fuelGoals] = await Promise.all([
    findWeeklyPlan({ store: deps.plans }, { member, weekStart }),
    deps.store.listForMember({ member, from: week.from, to: week.to }),
    deps.plans.fuelGoals(member, weekStart),
  ]);
  const shared = theirs.filter(({ audience }) => audience.includes(squad));
  return {
    trainedDays: trainedDays(theirs, week.days),
    plannedDays: plannedTrainingDays(plan.days, { weekDays: week.days, joinedOn }),
    weekStart,
    days: plan.days,
    marks: week.days.map((day) => markOn(shared, day)),
    fuelGoals: fuelGoals ?? [],
  };
}
