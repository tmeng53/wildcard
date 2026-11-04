import type { MemberId } from '../../domain/check-in.js';
import { trainedDays, weekOf } from '../../domain/days.js';
import { localDayAt, plannedTrainingDays, WeekStart } from '../../domain/weekly-plan.js';
import type { CheckInStore, Clock, MemberCalendar, WeeklyPlanStore } from '../../ports.js';
import { findWeeklyPlan } from '../weekly-plans.js';
import { zonesOf } from './member-zones.js';

/** A member's 本周 x/y: days trained this week against the days their plan trains. */
export interface MemberWeek {
  readonly trainedDays: number;
  readonly plannedDays: number;
}

/**
 * A member's own week as their player card shows it to a squadmate: their days trained, from all
 * their check-ins wherever they went, against their plan, in their own time zone (else the
 * viewer's), as the home counts the viewer's own week.
 */
export async function memberWeek(
  deps: {
    readonly store: CheckInStore;
    readonly plans: WeeklyPlanStore;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  { member, viewer }: { readonly member: MemberId; readonly viewer: MemberId },
): Promise<MemberWeek> {
  const zones = await zonesOf(deps.calendarOf, { members: [member, viewer], viewer });
  const { zone, joinedOn } = zones[0] ?? { zone: 'UTC', joinedOn: undefined };
  const week = weekOf(localDayAt(deps.clock(), zone));
  const [plan, theirs] = await Promise.all([
    findWeeklyPlan({ store: deps.plans }, { member, weekStart: WeekStart.parse(week.from) }),
    deps.store.listForMember({ member, from: week.from, to: week.to }),
  ]);
  return {
    trainedDays: trainedDays(theirs, week.days),
    plannedDays: plannedTrainingDays(plan.days, { weekDays: week.days, joinedOn }),
  };
}
