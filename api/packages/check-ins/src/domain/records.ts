import type { LocalDay } from './check-in.js';
import type { SportKey } from './sports.js';
import { addDays } from './weekly-plan.js';

// 外卡记录: a member's records since they joined, worked out from their check-ins and plans when
// asked, never stored. Pure: the caller loads the rows and passes the day and time zone.

/** One 训练 as the records read it. */
export interface RecordTraining {
  /** The day it counts for. */
  readonly day: LocalDay;
  /** The day it was posted; later than `day` for a 补打卡. */
  readonly postedDay: LocalDay;
  readonly madeAt: Date;
  readonly sport: SportKey;
  readonly customSport?: string;
  readonly minutes?: number;
}

/** A run of days in a row: how many, and the first and last day of it. */
export interface Streak {
  readonly days: number;
  readonly from: LocalDay;
  readonly to: LocalDay;
}

/** A sport and on how many days the member trained it. */
export interface SportDays {
  readonly sport: SportKey;
  readonly customSport?: string;
  readonly days: number;
}

export interface MemberRecords {
  /** Days with a 训练. */
  readonly trainedDays: number;
  /** Minutes of every 训练 that says how long it took. */
  readonly minutes: number;
  /** The longest single 训练, when one says how long it took. */
  readonly longestMinutes?: number;
  /** Most days trained in a row; a planned rest day between them neither breaks nor adds. */
  readonly longestStreak?: Streak;
  /** Most days in a row with a 健康餐. */
  readonly mealStreak?: Streak;
  /** 训练 by the hour of the member's clock they were posted at, 0 to 23; 补打卡 left out. */
  readonly hours: readonly number[];
  /** Days trained by weekday, Monday first. */
  readonly weekdays: readonly number[];
  /** The sports trained on the most days, most first, at most `TOP_SPORTS`. */
  readonly sports: readonly SportDays[];
  /** How many different sports the member trained. */
  readonly sportCount: number;
}

export const TOP_SPORTS = 3;

const sportKey = (training: { readonly sport: string; readonly customSport?: string }) =>
  training.sport === 'custom' ? `custom:${training.customSport ?? ''}` : training.sport;

/** Days trained at each sport, every sport counted, for comparing beyond a member's top ones. */
export function sportDays(trainings: readonly RecordTraining[]): ReadonlyMap<string, number> {
  const days = new Map<string, Set<LocalDay>>();
  for (const training of trainings) {
    const key = sportKey(training);
    days.set(key, (days.get(key) ?? new Set()).add(training.day));
  }
  return new Map([...days].map(([key, set]) => [key, set.size]));
}

/** 1 for Monday to 7 for Sunday. */
function weekdayOf(day: LocalDay): number {
  const weekday = new Date(Date.parse(day)).getUTCDay();
  return weekday === 0 ? 7 : weekday;
}

/** The hour, 0 to 23, on the wall clock of `timeZone` at `moment`. */
export function hourAt(moment: Date, timeZone: string): number {
  const hour = new Intl.DateTimeFormat('en-US', { timeZone, hour: '2-digit', hourCycle: 'h23' })
    .formatToParts(moment)
    .find((part) => part.type === 'hour')?.value;
  return Number(hour ?? 0) % 24;
}

/**
 * The longest run of `days` in a row. A day in `bridges` (a planned rest day) that isn't in
 * `days` neither breaks the run nor adds to it. The latest run wins a tie.
 */
export function longestRun(
  days: ReadonlySet<LocalDay>,
  bridges: ReadonlySet<LocalDay> = new Set(),
): Streak | undefined {
  const sorted = [...days].sort();
  const first = sorted[0];
  const last = sorted.at(-1);
  if (first === undefined || last === undefined) return undefined;
  let best: Streak | undefined;
  let run: { days: number; from: LocalDay; to: LocalDay } | undefined;
  for (let day = first; day <= last; day = addDays(day, 1)) {
    if (days.has(day)) {
      run =
        run === undefined
          ? { days: 1, from: day, to: day }
          : { ...run, days: run.days + 1, to: day };
      if (best === undefined || run.days >= best.days) best = { ...run };
    } else if (!bridges.has(day)) {
      run = undefined;
    }
  }
  return best;
}

/**
 * The run of `days` still going on `today` (外卡 on the player card): it ends on today or, while
 * today has none yet, on the day before, and a day in `bridges` without one neither breaks nor
 * adds, like `longestRun`. `streak` is none once a day without one that isn't a bridge broke it;
 * `brokeOn` is that day, so a caller that knows bridges only from some day on can tell whether
 * it looked far enough back.
 */
export function currentRun(
  days: ReadonlySet<LocalDay>,
  {
    today,
    bridges = new Set(),
  }: { readonly today: LocalDay; readonly bridges?: ReadonlySet<LocalDay> },
): { readonly streak?: Streak; readonly brokeOn?: LocalDay } {
  const first = [...days].sort()[0];
  if (first === undefined) return {};
  let run: { days: number; from: LocalDay; to: LocalDay } | undefined;
  // Today isn't over: not having one yet doesn't break the run.
  let day = days.has(today) ? today : addDays(today, -1);
  for (; day >= first; day = addDays(day, -1)) {
    if (days.has(day)) {
      run =
        run === undefined
          ? { days: 1, from: day, to: day }
          : { ...run, days: run.days + 1, from: day };
    } else if (!bridges.has(day)) {
      return { ...(run === undefined ? {} : { streak: run }), brokeOn: day };
    }
  }
  return run === undefined ? {} : { streak: run };
}

export function memberRecords(input: {
  readonly trainings: readonly RecordTraining[];
  readonly healthyMealDays: readonly LocalDay[];
  /** Days the member's plans made rest days, over the span of their trainings. */
  readonly restDays: ReadonlySet<LocalDay>;
  readonly timeZone: string;
}): MemberRecords {
  const trainedDays = new Set(input.trainings.map((training) => training.day));
  const hours = Array.from({ length: 24 }, () => 0);
  const weekdays = Array.from({ length: 7 }, () => 0);
  for (const training of input.trainings) {
    if (training.day !== training.postedDay) continue;
    const hour = hourAt(training.madeAt, input.timeZone);
    hours[hour] = (hours[hour] ?? 0) + 1;
  }
  for (const day of trainedDays) {
    const index = weekdayOf(day) - 1;
    weekdays[index] = (weekdays[index] ?? 0) + 1;
  }
  const bySport = new Map<string, { sport: SportDays; days: Set<LocalDay>; latest: number }>();
  for (const training of input.trainings) {
    const key = sportKey(training);
    const entry = bySport.get(key) ?? {
      sport: {
        sport: training.sport,
        ...(training.customSport === undefined ? {} : { customSport: training.customSport }),
        days: 0,
      },
      days: new Set<LocalDay>(),
      latest: 0,
    };
    entry.days.add(training.day);
    entry.latest = Math.max(entry.latest, training.madeAt.getTime());
    bySport.set(key, entry);
  }
  const sports = [...bySport.values()]
    .sort((a, b) => b.days.size - a.days.size || b.latest - a.latest)
    .slice(0, TOP_SPORTS)
    .map((entry) => ({ ...entry.sport, days: entry.days.size }));
  const minutes = input.trainings.flatMap((training) =>
    training.minutes === undefined ? [] : [training.minutes],
  );
  const longestStreak = longestRun(trainedDays, input.restDays);
  const mealStreak = longestRun(new Set(input.healthyMealDays));
  return {
    trainedDays: trainedDays.size,
    minutes: minutes.reduce((sum, value) => sum + value, 0),
    ...(minutes.length === 0 ? {} : { longestMinutes: Math.max(...minutes) }),
    ...(longestStreak === undefined ? {} : { longestStreak }),
    ...(mealStreak === undefined ? {} : { mealStreak }),
    hours,
    weekdays,
    sports,
    sportCount: bySport.size,
  };
}

/** What a member's squad records name them first in. */
export type SquadFirst = 'latestTrainer' | 'earliestTrainer' | 'mostDays' | 'topSport';

/** A squadmate and a count: the best partner's shared days, or the most cheers. */
export interface MateCount {
  readonly member: string;
  readonly count: number;
}

export interface SquadRecords {
  /** The squadmate who trained on the same day as the member the most days. */
  readonly partner?: MateCount;
  /** Reactions squadmates left on the member's check-ins, and who left the most. */
  readonly cheersReceived: { readonly count: number; readonly top?: MateCount };
  /** Reactions the member left on squadmates' check-ins, and on whose the most. */
  readonly cheersGiven: { readonly count: number; readonly top?: MateCount };
  /** What the member is first in the squad at, alone (never a tie, never "least"). */
  readonly firsts: readonly SquadFirst[];
}

/** The hour a member trains at most often, the latest on a tie; none without one. */
function usualHour(hours: readonly number[]): number | undefined {
  let best: number | undefined;
  hours.forEach((count, hour) => {
    if (count > 0 && (best === undefined || count >= (hours[best] ?? 0))) best = hour;
  });
  return best;
}

function top(counts: ReadonlyMap<string, number>): MateCount | undefined {
  let best: MateCount | undefined;
  for (const [member, count] of [...counts].sort(([a], [b]) => a.localeCompare(b))) {
    if (count > 0 && (best === undefined || count > best.count)) best = { member, count };
  }
  return best;
}

/** Whether `mine` is above every one of `theirs`; false without anyone to compare with. */
const firstAlone = (mine: number | undefined, theirs: readonly (number | undefined)[]) =>
  mine !== undefined &&
  theirs.some((value) => value !== undefined) &&
  theirs.every((value) => value === undefined || mine > value);

export function squadRecords(input: {
  /** The member's own records and trained days. */
  readonly me: { readonly records: MemberRecords; readonly days: ReadonlySet<LocalDay> };
  /** Each squadmate's records and trained days, from what they shared with the squad. */
  readonly mates: ReadonlyMap<
    string,
    {
      readonly records: MemberRecords;
      readonly days: ReadonlySet<LocalDay>;
      /** Days trained at each sport, from `sportDays`. */
      readonly sportDays: ReadonlyMap<string, number>;
    }
  >;
  /** Reactions on the member's check-ins, by squadmate. */
  readonly received: ReadonlyMap<string, number>;
  /** The member's reactions on squadmates' check-ins, by squadmate. */
  readonly given: ReadonlyMap<string, number>;
}): SquadRecords {
  const shared = new Map<string, number>();
  for (const [member, mate] of input.mates) {
    shared.set(member, [...mate.days].filter((day) => input.me.days.has(day)).length);
  }
  const partner = top(shared);
  const sum = (counts: ReadonlyMap<string, number>) =>
    [...counts.values()].reduce((total, count) => total + count, 0);
  const receivedTop = top(input.received);
  const givenTop = top(input.given);
  const mates = [...input.mates.values()].map((mate) => mate.records);
  // Night runs past midnight: training at 1am is later than at 11pm.
  const lateness = (records: MemberRecords) => {
    const hour = usualHour(records.hours);
    return hour === undefined ? undefined : (hour + 21) % 24;
  };
  const myHour = lateness(input.me.records);
  const theirHours = mates.map(lateness);
  const myTop = input.me.records.sports[0];
  const firsts: SquadFirst[] = [];
  if (firstAlone(myHour, theirHours)) firsts.push('latestTrainer');
  if (
    firstAlone(
      myHour === undefined ? undefined : -myHour,
      theirHours.map((hour) => (hour === undefined ? undefined : -hour)),
    )
  ) {
    firsts.push('earliestTrainer');
  }
  if (
    myTop !== undefined &&
    firstAlone(
      myTop.days,
      [...input.mates.values()].map((mate) => mate.sportDays.get(sportKey(myTop)) ?? 0),
    )
  ) {
    firsts.push('topSport');
  }
  if (
    input.me.records.trainedDays > 0 &&
    firstAlone(
      input.me.records.trainedDays,
      mates.map((records) => records.trainedDays),
    )
  ) {
    firsts.push('mostDays');
  }
  return {
    ...(partner === undefined ? {} : { partner }),
    cheersReceived: {
      count: sum(input.received),
      ...(receivedTop === undefined ? {} : { top: receivedTop }),
    },
    cheersGiven: { count: sum(input.given), ...(givenTop === undefined ? {} : { top: givenTop }) },
    firsts,
  };
}
