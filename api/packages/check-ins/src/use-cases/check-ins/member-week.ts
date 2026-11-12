import type { CheckInRecord, LocalDay, MemberId, SquadId } from '../../domain/check-in.js';
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
  /** Today on the squad's clock (else theirs): the row their 出赛表 shades as 今天. */
  readonly today: LocalDay;
}

/**
 * A member's own week as their player card shows it to a squadmate: their days trained, from all
 * their check-ins wherever they went, against their plan, in the week the squad's clock is in
 * (`squadZone`, so every squadmate sees the same week at once, Tracy 2026-11-09); and the card's back, their 出赛表 for this
 * week only (never another week's), whose marks come only from the posts shared to the squad the
 * card is read in, so a squadmate never learns what a post they can't see was.
 */
export async function memberWeek(
  deps: {
    readonly store: Pick<CheckInStore, 'listForMember'>;
    readonly plans: Pick<WeeklyPlanStore, 'savedFor' | 'templateFor' | 'trainedBy' | 'fuelGoals'>;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  {
    member,
    viewer,
    squad,
    squadZone,
  }: {
    readonly member: MemberId;
    readonly viewer: MemberId;
    readonly squad: SquadId;
    readonly squadZone: string;
  },
): Promise<MemberWeek> {
  const zones = await zonesOf(deps.calendarOf, { members: [member, viewer], viewer });
  const joinedOn = zones[0]?.joinedOn;
  const today = localDayAt(deps.clock(), squadZone);
  const week = weekOf(today);
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
    today,
  };
}

/**
 * A member's plan for a week as `squad` may see it (`daysSeenBy`): a day a 训练 the squad can't
 * see turned reads as the member planned it, so a check-in sent elsewhere never reaches the squad,
 * or its coach, through the plan.
 */
export async function planSharedTo(
  deps: {
    readonly store: Pick<CheckInStore, 'listForMember'>;
    readonly plans: Pick<WeeklyPlanStore, 'savedFor' | 'templateFor' | 'trainedBy'>;
  },
  {
    member,
    squad,
    weekStart,
  }: { readonly member: MemberId; readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<PlanDays> {
  const week = weekOf(weekStart);
  const [plan, trainedBy, theirs] = await Promise.all([
    findWeeklyPlan({ store: deps.plans }, { member, weekStart }),
    deps.plans.trainedBy(member, weekStart),
    deps.store.listForMember({ member, from: week.from, to: week.to }),
  ]);
  const shared = theirs.filter(({ audience }) => audience.includes(squad));
  const marks = week.days.map((day) => markOn(shared, day));
  return daysSeenBy({ plan: plan.days, trainedBy, marks, shared });
}

/**
 * The plan's days as the squad may see them. A 训练 turns its day into a training day of its
 * sport (`trainedOnDay`), so a day a 训练 turned that the squad can't see (sent elsewhere, or
 * deleted) shows as the sport of a 训练 that did come to this squad, else as the member planned it.
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
    const turn = trainedBy[String(index)];
    if (turn === undefined || seen.has(turn.checkIn)) return planned;
    const mark = marks[index];
    if (mark?.status !== 'trained') return turn.from;
    return mark.customSport === undefined
      ? { kind: 'train', sport: mark.sport }
      : { kind: 'train', sport: mark.sport, customSport: mark.customSport };
  });
}
