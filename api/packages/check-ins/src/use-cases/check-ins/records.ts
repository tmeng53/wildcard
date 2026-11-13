import { UNSAVED_MEMBER_ZONE } from '@wildcard/time-zones';
import type { MemberId, SquadId } from '../../domain/check-in.js';
import {
  memberRecords,
  sportDays,
  squadRecords,
  type MemberRecords,
  type RecordTraining,
  type SquadRecords,
  type Streak,
} from '../../domain/records.js';
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
  /** The 健康餐 run still going, beside `mealStreak`, as the player card's 外卡 counts it. */
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
  const going = await currentStreaks(deps, { member });
  const me = {
    ...memberRecords({
      trainings: mine,
      healthyMealDays: rows.healthyMealDays,
      cheatMealDays: rows.cheatMealDays,
      restDays: await restDays(deps, { member, days: mine.map((training) => training.day) }),
      leaveDays: new Set(rows.leaveDays),
      timeZone,
    }),
    ...(going.training === undefined ? {} : { currentStreak: going.training }),
    ...(going.meals === undefined ? {} : { currentMealStreak: going.meals }),
  };
  if (squad === undefined) return me;
  const shared = mine.filter((training) => training.inSquad);
  const squadMe = memberRecords({
    trainings: shared,
    healthyMealDays: [],
    cheatMealDays: [],
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
              cheatMealDays: [],
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
