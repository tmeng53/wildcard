import { UNSAVED_MEMBER_ZONE } from '@wildcard/time-zones';

import type { LocalDay, MemberId, SquadId } from '../../domain/check-in.js';
import { currentRun, mealBridges, type Streak } from '../../domain/records.js';
import { addDays, localDayAt, weekStartOf } from '../../domain/weekly-plan.js';
import type { CheckInStore, Clock, MemberCalendar, WeeklyPlanStore } from '../../ports.js';
import { restDays } from './rest-days.js';

/** The streaks still going that the player card's 外卡 show; each left out once broken. */
export interface CurrentStreaks {
  /** Days trained in a row, a planned rest day or an old 请假条 between them neither breaking nor adding. */
  readonly training?: Streak;
  /** Days in a row with a 健康餐; a 坦白放纵餐, a planned rest day or an old 请假条 neither breaks nor adds (`mealBridges`). */
  readonly meals?: Streak;
}

/** The weeks of plans read at first; most runs are shorter, and a longer one reads more. */
const FIRST_WEEKS = 2;

/**
 * A member's streaks still going on their own clock. With `squad`, only what they sent to it
 * counts, as a squadmate sees it, whether or not it was posted to 动态.
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
  const leave = new Set(days.leave);
  const cheatMeals = new Set(days.cheatMeals);
  // Rest days only as far back as a run reaches: read more weeks while one breaks before them.
  let from = addDays(weekStartOf(today), -7 * (FIRST_WEEKS - 1));
  const rest = await restDays(deps, { member, days: [from, today] });
  const runs = () => ({
    training: currentRun(new Set(days.trained), {
      today,
      bridges: new Set([...rest, ...leave]),
    }),
    meals: currentRun(new Set(days.healthyMeals), {
      today,
      bridges: mealBridges({ cheatMeals, restDays: rest, leave }),
    }),
  });
  let { training, meals } = runs();
  const brokeEarly = () =>
    [training.brokeOn, meals.brokeOn].some((day) => day !== undefined && day < from);
  while (brokeEarly()) {
    const earlier = addDays(
      from,
      -7 * Math.max(FIRST_WEEKS, Math.round(daysBetween(from, today) / 7)),
    );
    for (const day of await restDays(deps, { member, days: [earlier, addDays(from, -1)] })) {
      rest.add(day);
    }
    from = earlier;
    ({ training, meals } = runs());
  }
  return {
    ...(training.streak === undefined ? {} : { training: training.streak }),
    ...(meals.streak === undefined ? {} : { meals: meals.streak }),
  };
}

const daysBetween = (from: LocalDay, to: LocalDay) =>
  Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000);
