import { UNSAVED_MEMBER_ZONE } from '@wildcard/time-zones';
import type { LocalDay, MemberId, SquadId } from '../../domain/check-in.js';
import {
  memberRecords,
  sportDays,
  squadRecords,
  type MemberRecords,
  type RecordTraining,
  type SquadRecords,
} from '../../domain/records.js';
import { addDays, weekStartOf } from '../../domain/weekly-plan.js';
import type {
  CheckInStore,
  MemberCalendar,
  SquadMembership,
  WeeklyPlanStore,
} from '../../ports.js';
import { findWeeklyPlan } from '../weekly-plans.js';

/** 外卡记录: the member's records, and how they stand in their squad when they are in one. */
export interface Records extends MemberRecords {
  readonly squad?: SquadRecords & { readonly id: SquadId };
}

/** The days the member's plans made rest days, over the weeks from `from` to `to`. */
async function restDays(
  deps: { readonly plans: WeeklyPlanStore },
  { member, days }: { readonly member: MemberId; readonly days: readonly LocalDay[] },
): Promise<Set<LocalDay>> {
  const sorted = [...days].sort();
  const first = sorted[0];
  const last = sorted.at(-1);
  if (first === undefined || last === undefined) return new Set();
  const weeks: LocalDay[] = [];
  for (let week = weekStartOf(first); week <= last; week = addDays(week, 7)) weeks.push(week);
  const plans = await Promise.all(
    weeks.map((weekStart) =>
      findWeeklyPlan({ store: deps.plans }, { member, weekStart: weekStartOf(weekStart) }),
    ),
  );
  return new Set(
    plans.flatMap((plan) =>
      plan.days.flatMap((day, index) =>
        day.kind === 'rest' ? [addDays(plan.weekStart, index)] : [],
      ),
    ),
  );
}

export async function records(
  deps: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly plans: WeeklyPlanStore;
    readonly calendarOf: MemberCalendar;
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
  const me = memberRecords({
    trainings: mine,
    healthyMealDays: rows.healthyMealDays,
    restDays: await restDays(deps, { member, days: mine.map((training) => training.day) }),
    timeZone: await timeZoneOf(member),
  });
  if (squad === undefined) return me;
  const shared = mine.filter((training) => training.inSquad);
  const squadMe = memberRecords({
    trainings: shared,
    healthyMealDays: [],
    restDays: new Set(),
    timeZone: await timeZoneOf(member),
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
