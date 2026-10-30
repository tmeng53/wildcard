import type { MemberId, SquadId } from '../../domain/check-in.js';
import { weekOf } from '../../domain/days.js';
import { summarizeWeek, type WeekSummary } from '../../domain/week-summary.js';
import { localDayAt, plannedTrainingDays, type WeekStart } from '../../domain/weekly-plan.js';
import { SquadNotJoinedError, WeekNotStartedError } from '../../errors.js';
import type {
  CheckInStore,
  Clock,
  MemberCalendar,
  ReactionStore,
  SquadMembership,
  WeeklyPlanStore,
} from '../../ports.js';
import { findWeeklyPlan } from '../weekly-plans.js';
import { zonesOf } from './member-zones.js';

export interface SquadWeekSummary extends WeekSummary {
  readonly from: WeekStart;
  readonly to: string;
  /**
   * Every member's own Sunday is over. A check-in sent up to 48 hours late, a reaction left,
   * changed or taken off later, or a member joining or leaving can still change the numbers.
   */
  readonly final: boolean;
}

/**
 * A squad's week (周日战报) for one of its members: the week's awards and counts, from
 * check-ins sent to the squad by everyone in it now, against their plans. The week's days are
 * the same dates for everyone, each read in the member's own time zone, as check-ins are.
 */
export async function squadWeekSummary(
  deps: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly reactions: ReactionStore;
    readonly plans: WeeklyPlanStore;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  {
    viewer,
    squad,
    weekStart,
  }: { readonly viewer: MemberId; readonly squad: SquadId; readonly weekStart: WeekStart },
): Promise<SquadWeekSummary> {
  const { store, membership, reactions, plans, calendarOf, clock } = deps;
  const now = clock();
  const week = weekOf(weekStart);
  const memberIds = await membership.membersOf(squad);
  if (!memberIds.includes(viewer)) throw new SquadNotJoinedError(squad);

  const zones = await zonesOf(calendarOf, { members: memberIds, viewer });
  const todays = zones.map(({ member, zone }) => ({ member, today: localDayAt(now, zone) }));
  if (todays.some(({ member, today }) => member === viewer && today < week.from)) {
    throw new WeekNotStartedError(weekStart);
  }

  // A squad has at most 8 members, so one plan read each is fine.
  const [plansOf, checkIns] = await Promise.all([
    Promise.all(memberIds.map((member) => findWeeklyPlan({ store: plans }, { member, weekStart }))),
    store.listForSquad({ squad, members: memberIds, from: week.from, to: week.to }),
  ]);
  const members = memberIds.map((member, index) => ({
    member,
    plannedDays: plannedTrainingDays(plansOf[index]?.days ?? [], {
      weekDays: week.days,
      joinedOn: zones[index]?.joinedOn,
    }),
    checkIns: checkIns
      .filter((each) => each.member === member)
      .toSorted((a, b) => a.createdAt.getTime() - b.createdAt.getTime()),
  }));

  // Only reactions from members of the squad now, so none reveals another squad.
  const inSquad = new Set(memberIds);
  const all = await reactions.listForAll(checkIns.map(({ id }) => id));
  const fromSquad = new Map(
    [...all].map(([checkIn, each]) => [checkIn, each.filter(({ member }) => inSquad.has(member))]),
  );

  return {
    from: weekStart,
    to: week.to,
    final: todays.every(({ today }) => today > week.to),
    ...summarizeWeek({ week, members, reactions: fromSquad }, viewer),
  };
}
