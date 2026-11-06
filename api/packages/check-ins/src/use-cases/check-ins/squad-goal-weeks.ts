import type { MemberId, SquadId } from '../../domain/check-in.js';
import { trainedDays, weekOf } from '../../domain/days.js';
import { localDayAt, weekStartOf, type WeekStart } from '../../domain/weekly-plan.js';
import type { CheckInStore, Clock, MemberCalendar } from '../../ports.js';

/** The Monday of the member's week now, in their time zone (UTC before they have one). */
export async function weekStartNow(
  deps: { readonly calendarOf: MemberCalendar; readonly clock: Clock },
  member: MemberId,
): Promise<WeekStart> {
  const calendar = await deps.calendarOf(member);
  return weekStartOf(localDayAt(deps.clock(), calendar?.timeZone ?? 'UTC'));
}

/**
 * The days these members trained in the week starting `weekStart`, added up, from check-ins sent
 * to the squad, a day counting once however many times they trained: what the squad's weekly
 * goal counts.
 */
export async function squadTrainedDays(
  { store }: { readonly store: CheckInStore },
  {
    squad,
    members,
    weekStart,
  }: {
    readonly squad: SquadId;
    readonly members: readonly MemberId[];
    readonly weekStart: WeekStart;
  },
): Promise<number> {
  if (members.length === 0) return 0;
  const week = weekOf(weekStart);
  const checkIns = await store.listForSquad({ squad, members, from: week.from, to: week.to });
  return members.reduce(
    (sum, member) =>
      sum +
      trainedDays(
        checkIns.filter((each) => each.member === member),
        week.days,
      ),
    0,
  );
}
