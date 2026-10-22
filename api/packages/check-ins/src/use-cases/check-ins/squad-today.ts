import type { CheckInRecord, LocalDay, MemberId, SquadId } from '../../domain/check-in.js';
import {
  latestMealOn,
  trainedDays,
  trainingOn,
  weekOf,
  type TrainingStatus,
  type Week,
} from '../../domain/days.js';
import { localDayAt, plannedTrainingDays, WeekStart } from '../../domain/weekly-plan.js';
import { SquadNotJoinedError } from '../../errors.js';
import type {
  CheckInStore,
  Clock,
  MemberCalendar,
  SquadMembership,
  WeeklyPlanStore,
} from '../../ports.js';
import { findWeeklyPlan } from '../weekly-plans.js';
import { zonesOf } from './member-zones.js';

export interface SquadMemberToday {
  readonly member: MemberId;
  /** The member's own today, in their time zone, with the 3am grace. */
  readonly day: LocalDay;
  /** From check-ins sent to this squad only. */
  readonly training: TrainingStatus;
  readonly latestMeal: 'healthyMeal' | 'cheatMeal' | undefined;
  /** Today is a rest day in the member's weekly plan. */
  readonly plannedRest: boolean;
  /** When the member's first check-in today sent to this squad was made, of any kind. */
  readonly firstCheckInAt: Date | undefined;
}

export interface SquadToday {
  /**
   * Everyone in the squad now: first those who checked in today, by their first check-in; then
   * those on a planned rest day; then the rest. Ties keep the order members joined.
   */
  readonly members: readonly SquadMemberToday[];
  readonly trainedToday: number;
  /** Members whose today is a 请假条 with no 练了. */
  readonly disclaimerToday: number;
  /** Members on a planned rest day with no 练了 or 请假条. */
  readonly restingToday: number;
  /** At least one member trained today and every member who didn't is on a planned rest day (全员上场). */
  readonly everyoneTrained: boolean;
  /** The viewer's own week, from all their check-ins wherever they went, against their plan. */
  readonly myWeek: Week & { readonly trainedDays: number; readonly plannedDays: number };
  readonly myLifetimeTrainedDays: number;
  /**
   * Days trained and planned this week, added up over the members, each in their own week; trained
   * days from check-ins sent to this squad. Never split per member.
   */
  readonly squadWeek: { readonly trainedDays: number; readonly plannedDays: number };
}

function firstCheckInOn(checkIns: readonly CheckInRecord[], day: LocalDay): Date | undefined {
  let first: Date | undefined;
  for (const each of checkIns) {
    if (each.day === day && (first === undefined || each.createdAt < first)) first = each.createdAt;
  }
  return first;
}

/** Checked in today first (by first check-in), then on a planned rest day, then everyone else. */
function homeOrder(a: SquadMemberToday, b: SquadMemberToday): number {
  const group = (row: SquadMemberToday) => {
    if (row.firstCheckInAt !== undefined) return 0;
    return row.plannedRest ? 1 : 2;
  };
  const byGroup = group(a) - group(b);
  if (byGroup !== 0 || a.firstCheckInAt === undefined || b.firstCheckInAt === undefined) {
    return byGroup;
  }
  return a.firstCheckInAt.getTime() - b.firstCheckInAt.getTime();
}

/**
 * A squad's day as one of its members sees it on the home screen: where each member's today
 * stands, and the week's counts against the members' weekly plans. Each member's day and week are
 * their own, in their time zone.
 */
export async function squadToday(
  deps: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly plans: WeeklyPlanStore;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  { viewer, squad }: { readonly viewer: MemberId; readonly squad: SquadId },
): Promise<SquadToday> {
  const { store, membership, plans, calendarOf, clock } = deps;
  const now = clock();
  const memberIds = await membership.membersOf(squad);

  // A squad has at most 8 members, so one plan read each is fine.
  const zones = await zonesOf(calendarOf, { members: memberIds, viewer });
  const members = await Promise.all(
    zones.map(async ({ member, zone }) => {
      const day = localDayAt(now, zone);
      const week = weekOf(day);
      const plan = await findWeeklyPlan(
        { store: plans },
        { member, weekStart: WeekStart.parse(week.from) },
      );
      return { member, day, week, plan: plan.days };
    }),
  );
  const me = members.find(({ member }) => member === viewer);
  if (me === undefined) throw new SquadNotJoinedError(squad);

  const [squadCheckIns, mine, myTotals] = await Promise.all([
    store.listForSquad({
      squad,
      members: memberIds,
      from: members.map(({ week }) => week.from).reduce((a, b) => (a < b ? a : b)),
      to: members.map(({ week }) => week.to).reduce((a, b) => (a > b ? a : b)),
    }),
    store.listForMember({ member: viewer, from: me.week.from, to: me.week.to }),
    store.totals(viewer),
  ]);

  const rows = members.map(({ member, day, week, plan }) => {
    const theirs = squadCheckIns.filter((each) => each.member === member);
    const today: SquadMemberToday = {
      member,
      day,
      training: trainingOn(theirs, day),
      latestMeal: latestMealOn(theirs, day),
      plannedRest: plan[week.days.indexOf(day)]?.kind === 'rest',
      firstCheckInAt: firstCheckInOn(theirs, day),
    };
    return { today, trained: trainedDays(theirs, week.days), planned: plannedTrainingDays(plan) };
  });
  const todays = rows.map(({ today }) => today);
  const resting = ({ plannedRest, training }: SquadMemberToday) =>
    plannedRest && training === 'notCheckedIn';
  const trainedToday = todays.filter(({ training }) => training === 'trained').length;

  return {
    members: todays.toSorted(homeOrder),
    trainedToday,
    disclaimerToday: todays.filter(({ training }) => training === 'disclaimer').length,
    restingToday: todays.filter(resting).length,
    everyoneTrained:
      trainedToday > 0 &&
      todays.every(({ training, plannedRest }) => training === 'trained' || plannedRest),
    myWeek: {
      ...me.week,
      trainedDays: trainedDays(mine, me.week.days),
      plannedDays: plannedTrainingDays(me.plan),
    },
    myLifetimeTrainedDays: myTotals.trainedDays,
    squadWeek: {
      trainedDays: rows.reduce((sum, { trained }) => sum + trained, 0),
      plannedDays: rows.reduce((sum, { planned }) => sum + planned, 0),
    },
  };
}
