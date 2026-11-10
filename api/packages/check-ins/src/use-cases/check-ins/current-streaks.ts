import { UNSAVED_MEMBER_ZONE } from '@wildcard/time-zones';

import type { LocalDay, MemberId, SquadId } from '../../domain/check-in.js';
import { currentRun, type Streak } from '../../domain/records.js';
import { addDays, localDayAt, weekStartOf } from '../../domain/weekly-plan.js';
import type { CheckInStore, Clock, MemberCalendar, WeeklyPlanStore } from '../../ports.js';
import { restDays } from './records.js';

/** The streaks still going that the player card's 外卡 show; each left out once broken. */
export interface CurrentStreaks {
  /** Days trained in a row, a planned rest day between them neither breaking nor adding. */
  readonly training?: Streak;
  /** Days in a row with a meal checked in, a 健康餐 or a 坦白放纵餐. */
  readonly meals?: Streak;
}

/** The weeks of plans read at first; most runs are shorter, and a longer one reads more. */
const FIRST_WEEKS = 2;

/**
 * A member's streaks still going on their own clock. With `squad`, only what they shared to it
 * counts, as a squadmate sees it: a 仅自己可见 post never shows on another's screen.
 */
export async function currentStreaks(
  deps: {
    readonly store: CheckInStore;
    readonly plans: WeeklyPlanStore;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  { member, squad }: { readonly member: MemberId; readonly squad?: SquadId },
): Promise<CurrentStreaks> {
  const [days, calendar] = await Promise.all([
    deps.store.streakDays({ member, ...(squad === undefined ? {} : { squad }) }),
    deps.calendarOf(member),
  ]);
  const today = localDayAt(deps.clock(), calendar?.timeZone ?? UNSAVED_MEMBER_ZONE);
  const meals = currentRun(new Set(days.meals), { today }).streak;
  const trained = new Set(days.trained);
  // Rest days only as far back as the run reaches: read more weeks while it breaks before them.
  let from = addDays(weekStartOf(today), -7 * (FIRST_WEEKS - 1));
  const bridges = await restDays(deps, { member, days: [from, today] });
  let run = currentRun(trained, { today, bridges });
  while (run.brokeOn !== undefined && run.brokeOn < from) {
    const earlier = addDays(
      from,
      -7 * Math.max(FIRST_WEEKS, Math.round(daysBetween(from, today) / 7)),
    );
    for (const day of await restDays(deps, { member, days: [earlier, addDays(from, -1)] })) {
      bridges.add(day);
    }
    from = earlier;
    run = currentRun(trained, { today, bridges });
  }
  return {
    ...(run.streak === undefined ? {} : { training: run.streak }),
    ...(meals === undefined ? {} : { meals }),
  };
}

const daysBetween = (from: LocalDay, to: LocalDay) =>
  Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000);
