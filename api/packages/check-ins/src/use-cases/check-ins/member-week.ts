import type { CheckInRecord, MemberId, SquadId } from '../../domain/check-in.js';
import { markOn, trainedDays, weekOf, type DayMark } from '../../domain/days.js';
import type { FuelGoals } from '../../domain/fuel-goal.js';
import {
  localDayAt,
  plannedTrainingDays,
  WeekStart,
  weekStartOf,
  type PlanDay,
  type PlanDays,
  type TrainedBy,
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
  /** The Monday of the week they joined, in their time zone: their 出赛表's W1. */
  readonly firstWeek?: WeekStart;
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
  const [plan, trainedBy, theirs, fuelGoals] = await Promise.all([
    findWeeklyPlan({ store: deps.plans }, { member, weekStart }),
    deps.plans.trainedBy(member, weekStart),
    deps.store.listForMember({ member, from: week.from, to: week.to }),
    deps.plans.fuelGoals(member, weekStart),
  ]);
  const shared = theirs.filter(({ audience }) => audience.includes(squad));
  const marks = week.days.map((day) => markOn(shared, day));
  return {
    trainedDays: trainedDays(theirs, week.days),
    plannedDays: plannedTrainingDays(plan.days, { weekDays: week.days, joinedOn }),
    weekStart,
    days: daysSeenBy({ plan: plan.days, trainedBy, marks, shared }),
    marks,
    fuelGoals: fuelGoals ?? [],
    ...(joinedOn === undefined ? {} : { firstWeek: weekStartOf(joinedOn) }),
  };
}

/**
 * The plan's days as the squad may see them. A 练了 on a planned rest day turns that day into a
 * training day of its sport, so a day a 练了 turned that the squad can't see (sent elsewhere, or
 * deleted) shows as the rest day it was, or as the sport of a 练了 that did come to this squad.
 */
function daysSeenBy({
  plan,
  trainedBy,
  marks,
  shared,
}: {
  readonly plan: PlanDays;
  readonly trainedBy: TrainedBy;
  readonly marks: readonly DayMark[];
  readonly shared: readonly CheckInRecord[];
}): PlanDay[] {
  const seen = new Set<string>(shared.map(({ id }) => id));
  return plan.map((planned, index): PlanDay => {
    const turnedBy = trainedBy[String(index)];
    if (turnedBy === undefined || seen.has(turnedBy)) return planned;
    const mark = marks[index];
    if (mark?.status !== 'trained') return { kind: 'rest' };
    return mark.customSport === undefined
      ? { kind: 'train', sport: mark.sport }
      : { kind: 'train', sport: mark.sport, customSport: mark.customSport };
  });
}
