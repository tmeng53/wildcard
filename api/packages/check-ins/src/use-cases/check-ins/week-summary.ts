import type { MemberId, SquadId } from '../../domain/check-in.js';
import { weekOf } from '../../domain/days.js';
import { summarizeWeek, type WeekSummary } from '../../domain/week-summary.js';
import { localDayAt, type WeekStart } from '../../domain/weekly-plan.js';
import { SquadNotJoinedError, WeekNotStartedError } from '../../errors.js';
import type {
  CheckInStore,
  Clock,
  MemberCalendar,
  ReactionStore,
  WeeklyPlanStore,
} from '../../ports.js';
import { findWeeklyPlan } from '../weekly-plans.js';

/** The zone for a member who hasn't saved one, when the viewer hasn't either. */
const FALLBACK_ZONE = 'UTC';

export interface SquadWeekSummary extends WeekSummary {
  readonly from: WeekStart;
  readonly to: string;
  /** Every member's own Sunday is over, so the week's numbers won't change. */
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
  const { store, reactions, plans, calendarOf, clock } = deps;
  const now = clock();
  const week = weekOf(weekStart);
  const memberIds = await store.membersOf(squad);
  if (!memberIds.includes(viewer)) throw new SquadNotJoinedError(squad);

  // A squad has at most 8 members, so one calendar and one plan read each is fine.
  const calendars = await Promise.all(memberIds.map((member) => calendarOf(member)));
  const viewerZone = calendars[memberIds.indexOf(viewer)]?.timeZone ?? FALLBACK_ZONE;
  const todays = calendars.map((calendar) => localDayAt(now, calendar?.timeZone ?? viewerZone));
  if (localDayAt(now, viewerZone) < week.from) throw new WeekNotStartedError(weekStart);

  const [plansOf, checkIns] = await Promise.all([
    Promise.all(memberIds.map((member) => findWeeklyPlan({ store: plans }, { member, weekStart }))),
    store.listForSquad({ squad, from: week.from, to: week.to }),
  ]);
  const members = memberIds.map((member, index) => ({
    member,
    plannedDays: plansOf[index]?.days.filter(({ kind }) => kind === 'train').length ?? 0,
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
    final: todays.every((today) => today > week.to),
    ...summarizeWeek({ week, members, reactions: fromSquad }, viewer),
  };
}
