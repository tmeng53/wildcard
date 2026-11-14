import {
  MemberId as CheckInMember,
  SquadId as CheckInSquad,
  WeekStart as CheckInWeek,
  photosOf,
  type CheckInRecord,
  type CheckIns,
  type FuelSuggestion,
  type WeeklyPlans,
} from '@wildcard/check-ins';
import type {
  CoachMemberFacts,
  CoachStreaks,
  MemberFacts,
  PlanDayFacts,
  SquadWeekSource,
  TrainedTime,
  WeekCheckIn,
} from '@wildcard/coach';
import type { Members } from '@wildcard/members';
import type { Scenes } from '@wildcard/scenes';
import type { Sports } from '@wildcard/sports';
import { SceneWeek, SquadId as SquadsSquad, type Squads } from '@wildcard/squads';
import { wallClockAt } from '@wildcard/time-zones';
import { MemberId as AwardsMember, type WeeklyAwards } from '@wildcard/weekly-awards';

import { squadLanguages } from './squad-language.js';

// The coach across modules: who is in a squad from squads, its week from check-ins, its members'
// nicknames from members and sports' names from sports, in the shape the coach reads.

/** The suggested 饮食小目标 as the app's Simplified Chinese shows them (ScheduleUI's catalog). */
export const FUEL_WORDS: Readonly<Record<FuelSuggestion, string>> = {
  water: '喝够水',
  cookAtHome: '自己做饭',
  veggies: '每天有菜',
  lessBubbleTea: '奶茶减半',
  breakfast: '好好吃早餐',
  earlyDinner: '晚饭早点吃',
};

/** A squad's week as the coach sees it, up to `now`. */
export function coachSquadWeek(deps: {
  readonly checkIns: CheckIns;
  readonly members: Members;
  readonly squads: Squads;
  readonly sports: Sports;
  readonly scenes: Pick<Scenes, 'openOn'>;
  readonly clock: () => Date;
}): SquadWeekSource {
  return async ({ squad, weekStart }) => {
    const inSquad = await deps.squads.membersOf(SquadsSquad.parse(squad));
    const week = await deps.checkIns.squadWeekCheckIns({
      squad: CheckInSquad.parse(squad),
      weekStart: CheckInWeek.parse(weekStart),
      before: deps.clock(),
      members: inSquad.map((member) => CheckInMember.parse(member)),
    });
    const [squadmates, timeZones, languages, catalog, now] = await Promise.all([
      deps.members.squadmates(week.members.map(({ member }) => member)),
      deps.members.timeZones(week.members.map(({ member }) => member)),
      squadLanguages(deps, { squad, members: week.members.map(({ member }) => member) }),
      deps.sports.catalog(),
      deps.squads.squadAt({
        squad: SquadsSquad.parse(squad),
        week: SceneWeek.parse(weekStart),
        moment: deps.clock(),
        open: await deps.scenes.openOn(weekStart),
      }),
    ]);
    const sportNames = new Map(
      catalog.categories.flatMap(({ sports }) => sports.map(({ id, names }) => [id, names.zhHans])),
    );
    const checkIns = week.members
      .flatMap(({ checkIns: each }) => each)
      .toSorted((a, b) => a.createdAt.getTime() - b.createdAt.getTime())
      .map((record): WeekCheckIn => ({
        id: record.id,
        member: record.member,
        day: record.day,
        ...(record.postedDay === undefined || record.postedDay === record.day
          ? {}
          : { postedDay: record.postedDay }),
        createdAt: record.createdAt,
        ...postedTimeOf(record.createdAt, timeZones.get(record.member)),
        ...trainedTimeOf(record, timeZones.get(record.member)),
        kind: record.kind,
        // A check-in only recorded (发布到动态 off) counts with what was done (its sport and
        // minutes, as squadmates see on the member's card); its line and photos stay its author's.
        ...(record.inFeed
          ? { ...entryOf(record, sportNames), photos: photosOf(record).map(({ path }) => path) }
          : { ...withoutWords(entryOf(record, sportNames)), unposted: true as const }),
        reactedBy: (week.reactions.get(record.id) ?? [])
          .toSorted((a, b) => a.reactedAt.getTime() - b.reactedAt.getTime())
          .map(({ member }) => member),
        comments: (week.comments.get(record.id) ?? []).map(
          ({ id, member, text, commentedAt, replyTo, replyToCoach, mentions, mentionsCoach }) => ({
            id,
            member,
            text,
            at: commentedAt,
            ...(replyTo === undefined ? {} : { replyTo }),
            ...(replyToCoach === undefined ? {} : { toCoach: replyToCoach }),
            ...(mentions === undefined ? {} : { mentions }),
            ...(mentionsCoach === undefined ? {} : { mentionsCoach }),
          }),
        ),
      }));
    return {
      weekStart,
      ...(now === undefined ? {} : { name: now.name }),
      members: week.members.map(({ member }) => {
        const nickname = squadmates.get(member)?.character?.nickname;
        const language = languages.of(member);
        return nickname === undefined ? { member, language } : { member, nickname, language };
      }),
      language: languages.squad,
      checkIns,
    };
  };
}

/** When a check-in was posted on its author's own clock, `HH:MM`, when their zone is known. */
function postedTimeOf(createdAt: Date, zone: string | undefined): Pick<WeekCheckIn, 'postedTime'> {
  if (zone === undefined) return {};
  return { postedTime: clockWords(wallClockAt(createdAt, zone)) };
}

/**
 * When a 训练 was done on its author's clock, apart from when it was posted: the Apple Health
 * workout's start and end, else the start they typed.
 */
function trainedTimeOf(
  record: CheckInRecord,
  zone: string | undefined,
): { readonly trainedTime?: TrainedTime } {
  if (record.kind !== 'trained') return {};
  const { workout, startTime } = record.training;
  if (workout !== undefined && zone !== undefined) {
    const from = wallClockAt(new Date(workout.startedAt), zone);
    const to = wallClockAt(new Date(workout.endedAt), zone);
    return {
      trainedTime: {
        from: clockWords(from),
        to: clockWords(to),
        ...(from.day === record.day ? {} : { day: from.day }),
        source: 'health',
      },
    };
  }
  return startTime === undefined ? {} : { trainedTime: { from: startTime, source: 'typed' } };
}

function clockWords({ hour, minute }: { readonly hour: number; readonly minute: number }): string {
  return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

/** An entry without its member's line or place. */
function withoutWords(
  entry: Pick<WeekCheckIn, 'sport' | 'minutes' | 'text' | 'restDay' | 'place'>,
): Pick<WeekCheckIn, 'sport' | 'minutes' | 'restDay'> {
  const { sport, minutes, restDay } = entry;
  return {
    ...(sport === undefined ? {} : { sport }),
    ...(minutes === undefined ? {} : { minutes }),
    ...(restDay === undefined ? {} : { restDay }),
  };
}

/** A check-in's sport, minutes, line and place name, as the coach reads them. */
function entryOf(
  record: CheckInRecord,
  sportNames: ReadonlyMap<string, string>,
): Pick<WeekCheckIn, 'sport' | 'minutes' | 'text' | 'restDay' | 'place'> {
  switch (record.kind) {
    case 'trained': {
      const { sport, customSport, minutes, caption, place } = record.training;
      const name = customSport ?? sportNames.get(sport) ?? sport;
      return {
        sport: name,
        ...(minutes === undefined ? {} : { minutes }),
        ...(caption === undefined ? {} : { text: caption }),
        // Only the place's name: never its coordinates (Tracy, 2026-11-12).
        ...(place === undefined ? {} : { place: place.name }),
      };
    }
    case 'healthyMeal':
    case 'cheatMeal': {
      const { caption, place } = record.meal;
      return {
        ...(caption === undefined ? {} : { text: caption }),
        ...(place === undefined ? {} : { place: place.name }),
      };
    }
    case 'disclaimer':
      return {
        text: record.disclaimer.text,
        ...(record.disclaimer.restDay === true ? { restDay: true } : {}),
      };
  }
}

/**
 * What the coach can look up about members: their lifetime counts and top sport from
 * check-ins, their weekly titles from the awards, and this week's plan from the weekly plans,
 * the same numbers 我 and 出赛表 show.
 */
/** A member's streaks still going as their squad sees them, in days, for a 请假条's wake. */
export function coachStreaks(checkIns: Pick<CheckIns, 'currentStreaks'>): CoachStreaks {
  return async ({ squad, member }) => {
    const { training, meals } = await checkIns.currentStreaks({
      member: CheckInMember.parse(member),
      squad: CheckInSquad.parse(squad),
    });
    return {
      ...(training === undefined ? {} : { training: training.days }),
      ...(meals === undefined ? {} : { meals: meals.days }),
    };
  };
}

export function coachMemberFacts(deps: {
  readonly checkIns: CheckIns;
  readonly plans: WeeklyPlans;
  readonly awards: Pick<WeeklyAwards, 'titlesWon'>;
  readonly sports: Sports;
}): CoachMemberFacts {
  return async ({ squad, members, weekStart }) => {
    const catalog = await deps.sports.catalog();
    const sportNames = new Map(
      catalog.categories.flatMap(({ sports }) => sports.map(({ id, names }) => [id, names.zhHans])),
    );
    const nameOf = (sport: string | undefined, custom: string | undefined) =>
      custom ?? (sport === undefined ? undefined : (sportNames.get(sport) ?? sport));
    return Promise.all(
      members.map(async (member): Promise<MemberFacts> => {
        const [totals, plan, won] = await Promise.all([
          // Only what reached this squad: nothing from before the member joined it.
          deps.checkIns.totalsSharedTo({
            member: CheckInMember.parse(member),
            squad: CheckInSquad.parse(squad),
          }),
          deps.plans.find({
            member: CheckInMember.parse(member),
            weekStart: CheckInWeek.parse(weekStart),
          }),
          deps.awards.titlesWon(AwardsMember.parse(member)),
        ]);
        // The plan's days as the squad sees them: a day a 训练 sent elsewhere turned reads as planned.
        const days = await deps.checkIns.planSharedTo({
          member: CheckInMember.parse(member),
          squad: CheckInSquad.parse(squad),
          weekStart: CheckInWeek.parse(weekStart),
        });
        const top = totals.topSport;
        const topName = top === undefined ? undefined : nameOf(top.sport, top.customSport);
        return {
          member,
          trainedDays: totals.trainedDays,
          healthyMeals: totals.healthyMeals,
          cheatMeals: totals.cheatMeals,
          disclaimers: totals.disclaimers,
          ...(top === undefined || topName === undefined
            ? {}
            : { topSport: { name: topName, checkIns: top.checkIns } }),
          titles: won.count,
          ...(won.latest === undefined ? {} : { latestTitle: won.latest.title }),
          plan: days.map((day): PlanDayFacts => {
            if (day.kind === 'rest') return { kind: 'rest' };
            const sport = nameOf(day.sport, day.customSport);
            return sport === undefined ? { kind: 'train' } : { kind: 'train', sport };
          }),
          fuelGoals: plan.fuelGoals.map((goal) =>
            goal.kind === 'own' ? goal.text : FUEL_WORDS[goal.suggestion],
          ),
        };
      }),
    );
  };
}
