import { UNSAVED_MEMBER_ZONE } from '@wildcard/time-zones';
import type { MemberId, SquadId } from '../../domain/check-in.js';
import {
  currentRun,
  memberRecords,
  sportDays,
  squadRecords,
  type MemberRecords,
  type RecordTraining,
  type SquadRecords,
  type Streak,
} from '../../domain/records.js';
import { localDayAt } from '../../domain/weekly-plan.js';
import type {
  CheckInStore,
  Clock,
  MemberCalendar,
  SquadMembership,
  WeeklyPlanStore,
} from '../../ports.js';
import { currentStreaks } from './current-streaks.js';
import { restDays } from './rest-days.js';

/** 外卡记录: the member's records, and how they stand in their squad when they are in one. */
export interface Records extends MemberRecords {
  /** The days trained in a row still going, as the player card's 外卡 counts them. */
  readonly currentStreak?: Streak;
  /** The days in a row with a 健康餐 still going, beside `mealStreak`. */
  readonly currentMealStreak?: Streak;
  readonly squad?: SquadRecords & { readonly id: SquadId };
}

export async function records(
  deps: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly plans: WeeklyPlanStore;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  member: MemberId,
): Promise<Records> {
  // One squad a member at a time; the records count only it.
  const [squad] = [...(await deps.membership.squadIdsOf(member))];
  const mates =
    squad === undefined
      ? []
      : (await deps.membership.membersOf(squad)).filter((id) => id !== member);
  const rows = await deps.store.recordRows({
    member,
    ...(squad === undefined ? {} : { squad }),
    mates,
  });
  const byMember = new Map<MemberId, (RecordTraining & { readonly inSquad: boolean })[]>();
  for (const training of rows.trainings) {
    byMember.set(training.member, [...(byMember.get(training.member) ?? []), training]);
  }
  const timeZoneOf = async (id: MemberId) =>
    (await deps.calendarOf(id))?.timeZone ?? UNSAVED_MEMBER_ZONE;
  const mine = byMember.get(member) ?? [];
  const timeZone = await timeZoneOf(member);
  const current = (await currentStreaks(deps, { member })).training;
  const leaveDays = new Set(rows.leaveDays);
  const currentMeals = currentRun(new Set(rows.healthyMealDays), {
    today: localDayAt(deps.clock(), timeZone),
    bridges: leaveDays,
  }).streak;
  const me = {
    ...memberRecords({
      trainings: mine,
      healthyMealDays: rows.healthyMealDays,
      restDays: await restDays(deps, { member, days: mine.map((training) => training.day) }),
      leaveDays,
      timeZone,
    }),
    ...(current === undefined ? {} : { currentStreak: current }),
    ...(currentMeals === undefined ? {} : { currentMealStreak: currentMeals }),
  };
  if (squad === undefined) return me;
  const shared = mine.filter((training) => training.inSquad);
  const squadMe = memberRecords({
    trainings: shared,
    healthyMealDays: [],
    restDays: new Set(),
    leaveDays: new Set(),
    timeZone,
  });
  const mateRecords = new Map(
    await Promise.all(
      mates.map(async (mate) => {
        const trainings = byMember.get(mate) ?? [];
        return [
          mate,
          {
            records: memberRecords({
              trainings,
              healthyMealDays: [],
              restDays: new Set(),
              leaveDays: new Set(),
              timeZone: await timeZoneOf(mate),
            }),
            days: new Set(trainings.map((training) => training.day)),
            sportDays: sportDays(trainings),
          },
        ] as const;
      }),
    ),
  );
  return {
    ...me,
    squad: {
      id: squad,
      ...squadRecords({
        // Measured against squadmates on the same ground: only what the member shared with this squad.
        me: { records: squadMe, days: new Set(shared.map((training) => training.day)) },
        mates: mateRecords,
        received: rows.received,
        given: rows.given,
      }),
    },
  };
}
