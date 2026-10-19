import type { LocalDay, MemberId, SquadId } from '../../domain/check-in.js';
import {
  latestMealOn,
  trainedDays,
  trainingOn,
  weekOf,
  type TrainingStatus,
  type Week,
} from '../../domain/days.js';
import { localDayAt } from '../../domain/weekly-plan.js';
import { SquadNotJoinedError } from '../../errors.js';
import type { CheckInStore, Clock, MemberCalendar } from '../../ports.js';

/** The zone for a member who hasn't saved one, when the viewer hasn't either. */
const FALLBACK_ZONE = 'UTC';

export interface SquadMemberToday {
  readonly member: MemberId;
  /** The member's own today, in their time zone, with the 3am grace. */
  readonly day: LocalDay;
  /** From check-ins sent to this squad only. */
  readonly training: TrainingStatus;
  readonly latestMeal: 'healthyMeal' | 'cheatMeal' | undefined;
}

export interface SquadToday {
  /** Everyone in the squad now, in the order they joined. */
  readonly members: readonly SquadMemberToday[];
  readonly trainedToday: number;
  /** Members whose today is a 请假条 with no 练了. */
  readonly disclaimerToday: number;
  /** Every member has trained today. */
  readonly everyoneTrained: boolean;
  /** The viewer's own week, from all their check-ins wherever they went. */
  readonly myWeek: Week & { readonly trainedDays: number };
  readonly myLifetimeTrainedDays: number;
  /**
   * Days trained this week, added up over the members, each in their own week and from check-ins
   * sent to this squad. Never split per member.
   */
  readonly squadTrainedDays: number;
}

/**
 * A squad's day as one of its members sees it on the home screen: where each member's today
 * stands, and the week's counts. Each member's day and week are their own, in their time zone.
 */
export async function squadToday(
  deps: {
    readonly store: CheckInStore;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  { viewer, squad }: { readonly viewer: MemberId; readonly squad: SquadId },
): Promise<SquadToday> {
  const { store, calendarOf, clock } = deps;
  const now = clock();
  const memberIds = await store.membersOf(squad);

  // A squad has at most 8 members, so one calendar read each is fine.
  const calendars = await Promise.all(memberIds.map((member) => calendarOf(member)));
  const viewerZone = calendars[memberIds.indexOf(viewer)]?.timeZone ?? FALLBACK_ZONE;
  const members = memberIds.map((member, index) => {
    const day = localDayAt(now, calendars[index]?.timeZone ?? viewerZone);
    return { member, day, week: weekOf(day) };
  });
  const me = members.find(({ member }) => member === viewer);
  if (me === undefined) throw new SquadNotJoinedError(squad);

  const [squadCheckIns, mine, myLifetimeTrainedDays] = await Promise.all([
    store.listForSquad({
      squad,
      from: members.map(({ week }) => week.from).reduce((a, b) => (a < b ? a : b)),
      to: members.map(({ week }) => week.to).reduce((a, b) => (a > b ? a : b)),
    }),
    store.listForMember({ member: viewer, from: me.week.from, to: me.week.to }),
    store.countTrainedDays(viewer),
  ]);

  const rows = members.map(({ member, day, week }) => {
    const theirs = squadCheckIns.filter((each) => each.member === member);
    return {
      today: {
        member,
        day,
        training: trainingOn(theirs, day),
        latestMeal: latestMealOn(theirs, day),
      },
      trainedThisWeek: trainedDays(theirs, week.days),
    };
  });
  const todays = rows.map(({ today }) => today);

  return {
    members: todays,
    trainedToday: todays.filter(({ training }) => training === 'trained').length,
    disclaimerToday: todays.filter(({ training }) => training === 'disclaimer').length,
    everyoneTrained: todays.every(({ training }) => training === 'trained'),
    myWeek: { ...me.week, trainedDays: trainedDays(mine, me.week.days) },
    myLifetimeTrainedDays,
    squadTrainedDays: rows.reduce((sum, { trainedThisWeek }) => sum + trainedThisWeek, 0),
  };
}
